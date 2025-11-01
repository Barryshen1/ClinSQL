WITH cohort_adms AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 57 AND 67
),
septic_adms AS (
  SELECT DISTINCT ca.hadm_id
  FROM cohort_adms ca
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON ca.hadm_id = di.hadm_id
  WHERE (di.icd_version = 9 AND di.icd_code = '785.52')
     OR (di.icd_version = 10 AND di.icd_code = 'R65.21')
),
ultrasound_count AS (
  SELECT 
    proc.hadm_id, 
    COUNT(*) AS num_ultrasounds
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc 
    ON proc.icd_code = dproc.icd_code 
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ultrasound%' 
     OR LOWER(dproc.long_title) LIKE '%echocardiography%'
     OR LOWER(dproc.long_title) LIKE '%echo%'
     OR (proc.icd_version = 9 AND proc.icd_code LIKE '88.7%')
     OR (proc.icd_version = 10 AND proc.icd_code LIKE 'BW%')
  GROUP BY proc.hadm_id
)
SELECT 
  los_bin,
  icu_flag,
  APPROX_QUANTILES(num_ultrasounds, 5)[SAFE_OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_ultrasounds, 5)[SAFE_OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_ultrasounds, 5)[SAFE_OFFSET(3)] AS p75,
  COUNT(*) AS n_adms
FROM (
  SELECT 
    ca.hadm_id,
    ca.los_days,
    COALESCE(uc.num_ultrasounds, 0) AS num_ultrasounds,
    CASE 
      WHEN ca.los_days BETWEEN 1 AND 3 THEN '1-3 days' 
      WHEN ca.los_days BETWEEN 4 AND 7 THEN '4-7 days' 
    END AS los_bin,
    CASE 
      WHEN ia.hadm_id IS NOT NULL THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_flag
  FROM cohort_adms ca
  JOIN septic_adms sa 
    ON ca.hadm_id = sa.hadm_id
  LEFT JOIN ultrasound_count uc 
    ON ca.hadm_id = uc.hadm_id
  LEFT JOIN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays` 
    GROUP BY hadm_id
  ) ia 
    ON ca.hadm_id = ia.hadm_id
  WHERE (ca.los_days BETWEEN 1 AND 3) OR (ca.los_days BETWEEN 4 AND 7)
)
GROUP BY los_bin, icu_flag
ORDER BY los_bin, icu_flag;