WITH patients_filtered AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 69 AND 79
),
ugib_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code IN ('5780', '5781', '5789'))
     OR (icd_version = 10 AND icd_code IN ('K920', 'K921', 'K922', 'K924'))
),
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code IN ('49121', '49122'))
     OR (icd_version = 10 AND icd_code = 'J441')
),
qualifying_admissions AS (
  SELECT
    pf.hadm_id,
    TIMESTAMP_DIFF(pf.dischtime, pf.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM patients_filtered pf
  INNER JOIN ugib_admissions u ON pf.hadm_id = u.hadm_id
  INNER JOIN copd_admissions c ON pf.hadm_id = c.hadm_id
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM qualifying_admissions;