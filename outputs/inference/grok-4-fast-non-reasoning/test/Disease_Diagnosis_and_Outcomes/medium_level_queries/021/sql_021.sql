WITH cohort AS (
  -- Base admissions with patient demographics and ICU flag
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE WHEN c.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_icu,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  -- Filter: males 60-70 with at least one postoperative complication diagnosis
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE 'V90%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'Z98%')
        )
    )
),
charlson_weights AS (
  -- Approximate Charlson per admission (all diagnoses, weighted sum, distinct conditions)
  SELECT 
    d.subject_id,
    d.hadm_id,
    -- MI (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^410|I21|I22') THEN 1 ELSE 0 END) AS mi,
    -- CHF (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^428|I50|I09\.9|I11\.0|I13\.(0|2)') THEN 1 ELSE 0 END) AS chf,
    -- PVD (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^443\.9|I70') THEN 1 ELSE 0 END) AS pvd,
    -- Dementia (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^290|F0[1-3]') THEN 1 ELSE 0 END) AS dementia,
    -- COPD (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^496|J44') THEN 1 ELSE 0 END) AS copd,
    -- Diabetes uncomplicated (1), complicated (2)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^250\.[12]') OR REGEXP_CONTAINS(d.icd_code, r'^E[0-9][0-9]\.[12]') THEN 1 ELSE 0 END) +
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^250\.[3-9]') OR REGEXP_CONTAINS(d.icd_code, r'^E[0-9][0-9]\.[3-9]') THEN 1 ELSE 0 END) AS diabetes,
    -- Hemiplegia (2)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^342|G81') THEN 2 ELSE 0 END) AS hemiplegia,
    -- Renal (2)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^(582|585|586|V56(\.[0-9]+)?)|N1[8-9]|Z99\.2') THEN 2 ELSE 0 END) AS renal,
    -- Cancer (2)
    MAX(CASE WHEN (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^(14[0-9]|16[0-7]|17[0-9])')) OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^C[0-7][0-9]|C8[0-9]|D0[0-4]'))
    ) THEN 2 ELSE 0 END) AS cancer,
    -- Metastatic (6) - overrides solid cancer
    MAX(CASE WHEN (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^19[0-9]\.(0|8)')) OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^C77|C78|C79|C80'))
    ) THEN 6 ELSE 0 END) AS metastatic,
    -- Liver mild (1)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^571\.5|K70\.0|K7[3-4]|K76\.6') THEN 1 ELSE 0 END) AS liver_mild,
    -- Liver mod-severe (3)
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^(456\.[0-2]|572\.(4|8)|K717)') THEN 3 ELSE 0 END) AS liver_severe
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN cohort c ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
  -- Exclude the postop complication ICD itself to avoid inflating score
  WHERE NOT (
    (d.icd_version = 9 AND d.icd_code LIKE 'V90%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'Z98%')
  )
  GROUP BY d.subject_id, d.hadm_id
),
charlson AS (
  SELECT 
    c.*,
    COALESCE(
      mi + chf + pvd + dementia + copd + diabetes + hemiplegia + renal + 
      metastatic + liver_mild + liver_severe, 0
    ) AS charlson_score
  FROM cohort c
  LEFT JOIN charlson_weights cw 
    ON c.subject_id = cw.subject_id AND c.hadm_id = cw.hadm_id
),
stratified AS (
  SELECT 
    *,
    CASE 
      WHEN los_days <= 3 THEN '1-3'
      WHEN los_days <= 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    CASE 
      WHEN COALESCE(charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(charlson_score, 0) <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bin,
    -- Time to death in days (for decedents)
    CASE 
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL 
      THEN DATE_DIFF(deathtime, admittime, HOUR) / 24.0
      ELSE NULL
    END AS time_to_death_days
  FROM charlson
),
summary AS (
  SELECT 
    is_icu,
    los_bin,
    charlson_bin,
    COUNT(DISTINCT hadm_id) AS n,
    SUM(hospital_expire_flag) AS deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100 AS mortality_pct,
    -- Pre-compute median time-to-death for decedents in this group
    (SELECT PERCENTILE_CONT(time_to_death_days, 0.5)
     FROM stratified str 
     WHERE str.is_icu = stratified.is_icu 
       AND str.los_bin = stratified.los_bin
       AND str.charlson_bin = stratified.charlson_bin
       AND str.hospital_expire_flag = 1 
       AND str.time_to_death_days IS NOT NULL
    ) AS median_time_to_death_days
  FROM stratified
  GROUP BY is_icu, los_bin, charlson_bin
)
SELECT 
  CASE WHEN s.is_icu THEN 'ICU' ELSE 'Non-ICU' END AS cohort_type,
  s.los_bin,
  s.charlson_bin,
  s.n,
  ROUND(s.mortality_pct, 2) AS mortality_pct,
  ROUND(s.median_time_to_death_days, 1) AS median_time_to_death_days
FROM summary s
ORDER BY cohort_type, los_bin, charlson_bin;