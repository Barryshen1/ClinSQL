WITH ich_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 68 AND 78
  AND d_diag.long_title LIKE '%Intracranial hemorrhage%'
),
cohort_metrics AS (
  SELECT 
    COUNT(DISTINCT ip.subject_id) AS cohort_size,
    SUM(CASE WHEN a.deathtime IS NOT NULL AND a.deathtime <= DATETIME_ADD(a.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) / COUNT(DISTINCT ip.subject_id) AS mortality_30day,
    SUM(CASE WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` l WHERE l.hadm_id = a.hadm_id AND l.itemid = 50861 AND l.valuenum > 1.2) THEN 1 ELSE 0 END) / COUNT(DISTINCT ip.subject_id) AS aki_rate,
    SUM(CASE WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` c WHERE c.hadm_id = a.hadm_id AND c.itemid = 220339 AND c.valuenum = 1) THEN 1 ELSE 0 END) / COUNT(DISTINCT ip.subject_id) AS ards_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN ich_patients ip ON a.hadm_id = ip.hadm_id
),
decedent_survival AS (
  SELECT 
    APPROX_QUANTILES(DATE_DIFF(p.dod, a.dischtime, DAY), 100)[OFFSET(50)] AS median_survival_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN ich_patients ip ON a.hadm_id = ip.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hospital_expire_flag = 1 AND p.dod IS NOT NULL
)
SELECT 
  cohort_size,
  mortality_30day,
  aki_rate,
  ards_rate,
  (SELECT median_survival_days FROM decedent_survival) AS median_survival_days
FROM cohort_metrics;