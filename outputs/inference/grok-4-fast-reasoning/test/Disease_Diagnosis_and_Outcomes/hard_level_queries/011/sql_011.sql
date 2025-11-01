WITH base_cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime, 
    p.dod, 
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age AS age_at_adm,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
    )
),
cohort AS (
  SELECT * 
  FROM base_cohort
  WHERE age_at_adm >= 88 AND age_at_adm <= 98
),
decedents AS (
  SELECT 
    DATE_DIFF(dod, DATE(admittime), DAY) AS survival_days
  FROM cohort
  WHERE dod IS NOT NULL
),
median_surv AS (
  SELECT PERCENTILE_CONT(survival_days, 0.5) AS median_survival_days
  FROM decedents
),
aki_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN cohort c ON d.hadm_id = c.hadm_id
  WHERE (
    (d.icd_version = 9 AND d.icd_code LIKE '584%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
  )
),
ards_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN cohort c ON d.hadm_id = c.hadm_id
  WHERE (
    (d.icd_version = 9 AND d.icd_code LIKE '5185%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'J80%')
  )
)
SELECT 
  COUNT(*) AS total_cohort_size,
  SUM(IF(dod IS NOT NULL AND DATE_DIFF(dod, DATE(admittime), DAY) <= 30, 1, 0)) * 1.0 / COUNT(*) AS day30_mortality_rate,
  (SELECT COUNT(*) FROM aki_hadm) * 1.0 / COUNT(*) AS aki_rate,
  (SELECT COUNT(*) FROM ards_hadm) * 1.0 / COUNT(*) AS ards_rate,
  (SELECT median_survival_days FROM median_surv) AS median_survival_days
FROM cohort;