WITH copd_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chronic obstructive%'
     OR LOWER(long_title) LIKE '%copd%'
     OR (icd_version = 9 AND icd_code IN ('491', '492', '496'))
     OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('J43', 'J44'))
),
acs_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%ischemic heart%'
     OR LOWER(long_title) LIKE '%acute coronary%'
     OR LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%angina%'
     OR (icd_version = 9 AND icd_code BETWEEN '410' AND '414')
     OR (icd_version = 10 AND SUBSTR(icd_code, 1, 2) = 'I2')
),
admissions_with_copd AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE EXISTS (
    SELECT 1
    FROM copd_codes c
    WHERE c.icd_code = di.icd_code
      AND c.icd_version = di.icd_version
  )
),
admissions_with_acs AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE EXISTS (
    SELECT 1
    FROM acs_codes a
    WHERE a.icd_code = di.icd_code
      AND a.icd_version = di.icd_version
  )
),
eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN admissions_with_copd c ON a.hadm_id = c.hadm_id
  INNER JOIN admissions_with_acs s ON a.hadm_id = s.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_calc AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON e.hadm_id = a.hadm_id
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM los_calc;