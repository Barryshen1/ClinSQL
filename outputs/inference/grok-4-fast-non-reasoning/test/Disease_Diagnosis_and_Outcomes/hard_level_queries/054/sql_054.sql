WITH elixhauser_weights AS (
  -- Expanded Elixhauser van Walraven weights (key conditions; full 31 in production)
  SELECT 'CHF' AS condition, 3 AS weight, 
    ARRAY[r'^(I50|I11\.0|I13\.0|I13\.2|I25\.5|I42\.0|I42\.5-I42\.9|I43|P29\.0)$'] AS icd10_patterns,
    ARRAY[r'^39(8|84)'] AS icd9_patterns
  UNION ALL SELECT 'DM', -2, ARRAY[r'^E10-E14'], ARRAY[r'^250']
  UNION ALL SELECT 'COPD', 3, ARRAY[r'^J40-J47'], ARRAY[r'^490-496']
  UNION ALL SELECT 'HTN', 0, ARRAY[r'^I10'], ARRAY[r'^401']
  UNION ALL SELECT 'Renal', 4, ARRAY[r'^N17-N19|I12|I13\.1'], ARRAY[r'^585']
  UNION ALL SELECT 'Cancer', 3, ARRAY[r'^C00-D48'], ARRAY[r'^14[0-9]']
  UNION ALL SELECT 'Liver', 2, ARRAY[r'^K70-K77'], ARRAY[r'^57[0-1]']
  -- Add remaining as needed (e.g., HIV=-1, Obesity=-1, etc.)
),
patient_comorbidities AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    SUM(ew.weight) AS van_walraven_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  CROSS JOIN elixhauser_weights ew
  WHERE (
    (di.icd_version = '10' AND EXISTS (SELECT 1 FROM UNNEST(ew.icd10_patterns) p WHERE REGEXP_CONTAINS(di.icd_code, p)))
    OR (di.icd_version = '9' AND EXISTS (SELECT 1 FROM UNNEST(ew.icd9_patterns) p WHERE REGEXP_CONTAINS(di.icd_code, p)))
  )
  GROUP BY di.subject_id, di.hadm_id
),
elixhauser_per_adm AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    COALESCE(pc.van_walraven_score, 0) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN patient_comorbidities pc ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type != 'OBSERVATION'  -- Inpatients only
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1  -- First admission per patient
),
pe_flags AS (
  SELECT 
    subject_id, hadm_id,
    LOGICAL_OR(
      CASE 
        WHEN icd_version = '10' AND REGEXP_CONTAINS(icd_code, r'^I26') THEN TRUE
        WHEN icd_version = '9' AND REGEXP_CONTAINS(icd_code, r'^415\.1$') THEN TRUE
        ELSE FALSE 
      END
    ) AS has_pe
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
pe_cohort AS (
  SELECT 
    ea.*,
    COALESCE(pf.has_pe, FALSE) AS has_pe,
    CASE WHEN COALESCE(pf.has_pe, FALSE) THEN 1 ELSE 0 END AS cohort_flag  -- 1: PE, 0: no PE
  FROM elixhauser_per_adm ea
  LEFT JOIN pe_flags pf ON ea.subject_id = pf.subject_id AND ea.hadm_id = pf.hadm_id
),
complications AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.cohort_flag,
    pc.has_pe,
    pc.comorbidity_score,
    MAX(CASE WHEN d.seq_num > 1 AND REGEXP_CONTAINS(d.icd_code, r'^(I30-I52)$') THEN 1 ELSE 0 END) AS has_cardio_comp,
    MAX(CASE WHEN d.seq_num > 1 AND REGEXP_CONTAINS(d.icd_code, r'^(G45|I63)$') THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM pe_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pc.subject_id = d.subject_id AND pc.hadm_id = d.hadm_id
  GROUP BY pc.subject_id, pc.hadm_id, pc.cohort_flag, pc.has_pe, pc.comorbidity_score
),
target_vs_control AS (
  SELECT 
    cohort_flag,
    COUNT(*) AS n_admissions,
    AVG(comorbidity_score) AS mean_comorbidity_score,
    -- 30-day mortality (in-hospital or within 30 days post-admit)
    AVG(CASE 
      WHEN hospital_expire_flag = 1 
        OR DATE_DIFF(COALESCE(deathtime, dischtime), admittime, DAY) <= 30 
      THEN 1.0 
      ELSE 0.0 
    END) AS mortality_30d_rate,
    -- Survivor LOS (hospital LOS in days for non-expired)
    AVG(CASE 
      WHEN hospital_expire_flag = 0 
      THEN DATE_DIFF(dischtime, admittime, DAY) 
      ELSE NULL 
    END) AS mean_los_survivors,
    AVG(CASE WHEN has_cardio_comp = 1 THEN 1.0 ELSE 0.0 END) AS cardio_comp_rate,
    AVG(CASE WHEN has_neuro_comp = 1 THEN 1.0 ELSE 0.0 END) AS neuro_comp_rate
  FROM complications
  WHERE (cohort_flag = 1 AND comorbidity_score >= 5)  -- Target: PE + high comorbidity
     OR (cohort_flag = 0)  -- Controls: no PE, same age/gender
  GROUP BY cohort_flag
),
percentile_calc AS (
  SELECT 
    (SELECT AVG(comorbidity_score) FROM complications WHERE cohort_flag = 1 AND has_pe = TRUE AND comorbidity_score >= 5) AS target_mean_score,
    PERCENT_RANK() OVER (ORDER BY comorbidity_score) AS rank_in_controls
  FROM complications 
  WHERE cohort_flag = 0
  QUALIFY ABS(comorbidity_score - (SELECT AVG(comorbidity_score) FROM complications WHERE cohort_flag = 1 AND has_pe = TRUE AND comorbidity_score >= 5)) = 
         MIN(ABS(comorbidity_score - (SELECT AVG(comorbidity_score) FROM complications WHERE cohort_flag = 1 AND has_pe = TRUE AND comorbidity_score >= 5)) 
             OVER (PARTITION BY NULL))
)
SELECT 
  CASE WHEN tvc.cohort_flag = 1 THEN 'Target (PE + High Comorbidity)' ELSE 'Controls (Same Age, No PE)' END AS group_desc,
  tvc.mean_comorbidity_score,
  tvc.mortality_30d_rate,
  tvc.cardio_comp_rate,
  tvc.neuro_comp_rate,
  tvc.mean_los_survivors,
  CASE WHEN tvc.cohort_flag = 1 THEN pc.target_mean_score * 100 ELSE NULL END AS percentile_vs_controls  -- Approx percentile as rank * 100
FROM target_vs_control tvc
CROSS JOIN (SELECT target_mean_score FROM percentile_calc LIMIT 1) pc
ORDER BY cohort_flag;