WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 88 AND 98
  AND d_diag.long_title LIKE '%Pneumonia%'
),
metrics AS (
  SELECT 
    c.subject_id,
    a.hospital_expire_flag,
    CASE WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` l WHERE l.hadm_id = c.hadm_id AND l.itemid = 50861 AND l.valuenum > 2) THEN 1 ELSE 0 END AS aki_flag,
    CASE WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d WHERE d.hadm_id = c.hadm_id AND d.icd_code = 'J80') THEN 1 ELSE 0 END AS ards_flag,
    DATE_DIFF(CASE WHEN a.deathtime IS NOT NULL THEN a.deathtime ELSE p.dod END, a.admittime, DAY) AS survival_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
)
SELECT 
  COUNT(DISTINCT subject_id) AS cohort_size,
  MIN(survival_days) AS min_survival_days,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(25)] AS q1_survival_days,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(75)] AS q3_survival_days,
  MAX(survival_days) AS max_survival_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id) AS in_hospital_mortality,
  SUM(aki_flag) / COUNT(DISTINCT subject_id) AS aki_rate,
  SUM(ards_flag) / COUNT(DISTINCT subject_id) AS ards_rate
FROM metrics
WHERE hospital_expire_flag = 1;