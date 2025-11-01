WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0')  -- ICD-10 codes for ACS
     OR (d.icd_code LIKE '410%' OR d.icd_code = '411.1')  -- ICD-9 codes: 410.* (AMI), 411.1 (unstable angina)
),
first_troponin AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.valuenum AS first_troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN acs_admissions acs 
    ON le.subject_id = acs.subject_id AND le.hadm_id = acs.hadm_id
  WHERE le.itemid = 51003  -- Troponin T
    AND le.valuenum > 0.01
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY le.subject_id, le.hadm_id 
    ORDER BY le.charttime
  ) = 1
),
cohort AS (
  SELECT 
    p.subject_id, 
    adm.hadm_id, 
    ft.first_troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN first_troponin ft
    ON adm.subject_id = ft.subject_id AND adm.hadm_id = ft.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
)
SELECT 
  APPROX_QUANTILES(first_troponin_value, 4)[OFFSET(1)] AS median,
  APPROX_QUANTILES(first_troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(first_troponin_value, 4)[OFFSET(1)] AS iqr
FROM cohort;