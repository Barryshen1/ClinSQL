WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

pneumonia_cases AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    fa.hadm_id = di.hadm_id
  WHERE
    fa.admission_rank = 1  -- First admission only
    AND (
      -- ICD-10 codes for pneumonia (J12-J18)
      (di.icd_version = 10 AND (di.icd_code LIKE 'J12%' OR di.icd_code LIKE 'J13%' OR di.icd_code LIKE 'J14%' OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J17%' OR di.icd_code LIKE 'J18%'))
      OR
      -- ICD-9 codes for pneumonia (480-486)
      (di.icd_version = 9 AND (di.icd_code LIKE '480%' OR di.icd_code LIKE '481%' OR di.icd_code LIKE '482%' OR di.icd_code LIKE '483%' OR di.icd_code LIKE '484%' OR di.icd_code LIKE '485%' OR di.icd_code LIKE '486%'))
    )
)

SELECT
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100 AS mortality_rate_percentage
FROM
  pneumonia_cases;