WITH cohort AS (
  -- Base cohort: males 78-88 with principal AMI
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d1.seq_num = 1
    AND d1.icd_version = '10'
    AND (d1.icd_code LIKE 'I21%' OR d1.icd_code LIKE 'I22%')
    AND a.dischtime > a.admittime  -- Valid LOS
),

exclusions AS (
  -- Exclude shock or respiratory failure (any diagnosis)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = '10'
    AND (icd_code = 'R57.0' OR icd_code LIKE 'J96%')
),

comorb_flags AS (
  -- Comorbidities from all diagnoses
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Simple count-based burden (major conditions)
    (CASE WHEN SUM(CASE 
      WHEN di.icd_code IN ('I09.9', 'I11.0', 'I13.0', 'I13.2', 'I25.5', 'I42.0', 'I42.5', 'I42.6', 'I42.7', 'I42.8', 'I42.9') 
        OR di.icd_code LIKE 'I43%' OR di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'I12%' OR di.icd_code LIKE 'I13%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'I70%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code = 'I10' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'G45%' OR di.icd_code LIKE 'G46%' OR di.icd_code LIKE 'H34.0%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'J40%' OR di.icd_code LIKE 'J41%' OR di.icd_code LIKE 'J42%' OR di.icd_code LIKE 'J43%' OR di.icd_code LIKE 'J44%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
     CASE WHEN SUM(CASE WHEN di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS comorb_count
    -- CKD and DM flags
    , MAX(CASE WHEN di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd
    , MAX(CASE WHEN di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_dm
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  WHERE di.icd_version = '10'
  GROUP BY c.subject_id, c.hadm_id
),

base_cohort AS (
  SELECT 
    c.*,
    cf.comorb_count,
    CASE 
      WHEN cf.comorb_count <= 1 THEN 'Low'
      WHEN cf.comorb_count <= 3 THEN 'Medium'
      ELSE 'High'
    END AS comorb_burden,
    cf.has_ckd,
    cf.has_dm,
    NTILE(4) OVER (ORDER BY c.los_days) AS los_quartile
  FROM cohort c
  INNER JOIN comorb_flags cf ON c.subject_id = cf.subject_id AND c.hadm_id = cf.hadm_id
  LEFT JOIN exclusions e ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.hadm_id IS NULL  -- No exclusions
)

-- Mortality by LOS quartile and comorbidity burden, with 95% CI (Wilson score) and prevalences
SELECT 
  los_quartile,
  comorb_burden,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS mort_count,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_pct,
  -- 95% CI lower (Wilson)
  ( (mort_count + POWER(1.96, 2) / 4) / total_patients - 1.96 * SQRT( (mort_count * (total_patients - mort_count) / total_patients + POWER(1.96, 2) / 4) / POWER(total_patients, 2) ) ) * 100 AS ci_lower,
  -- 95% CI upper (Wilson)
  ( (mort_count + POWER(1.96, 2) / 4) / total_patients + 1.96 * SQRT( (mort_count * (total_patients - mort_count) / total_patients + POWER(1.96, 2) / 4) / POWER(total_patients, 2) ) ) * 100 AS ci_upper,
  SAFE_DIVIDE(SUM(has_ckd), COUNT(*)) * 100 AS ckd_prevalence_pct,
  SAFE_DIVIDE(SUM(has_dm), COUNT(*)) * 100 AS dm_prevalence_pct
FROM base_cohort
GROUP BY los_quartile, comorb_burden
ORDER BY los_quartile, 
  CASE comorb_burden WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;