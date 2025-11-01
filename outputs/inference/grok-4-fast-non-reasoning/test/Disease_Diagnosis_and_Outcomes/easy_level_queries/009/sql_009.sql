WITH ihd_cohort AS (
  -- Patients with ischemic heart disease/ACS (ICD-10: I20, I21, I25)
  SELECT DISTINCT 
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE CAST(d.icd_version AS STRING) = '10'
    AND REGEXP_CONTAINS(icd.icd_code, r'^I(20|21|25)')
),
copd_cohort AS (
  -- Patients with COPD (ICD-10: J44)
  SELECT DISTINCT 
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE CAST(d.icd_version AS STRING) = '10'
    AND REGEXP_CONTAINS(icd.icd_code, r'^J44')
),
cohort AS (
  -- Intersection: patients with both conditions
  SELECT DISTINCT 
    ihd.subject_id
  FROM ihd_cohort ihd
  INNER JOIN copd_cohort copd
    ON ihd.subject_id = copd.subject_id
),
los_data AS (
  SELECT 
    p.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN cohort c
    ON p.subject_id = c.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime > a.admittime  -- Valid LOS only
    AND a.hospital_expire_flag = 0  -- Optional: exclude in-hospital deaths for LOS percentile
)
SELECT 
  COUNT(*) AS cohort_size,
  PERCENTILE_CONT(0.75) OVER() AS p75_los_days
FROM los_data
WHERE los_days IS NOT NULL;