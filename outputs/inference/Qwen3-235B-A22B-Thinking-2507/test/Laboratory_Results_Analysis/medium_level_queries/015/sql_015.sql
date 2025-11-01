WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 88 AND 98
),
acs_admissions AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND icd_version = 10
    AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%')
),
target_admissions AS (
  SELECT 
    pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN acs_admissions aa
    ON pa.hadm_id = aa.hadm_id
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN target_admissions ta
    ON le.hadm_id = ta.hadm_id
  WHERE le.itemid = 50184
    AND le.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr
FROM first_troponin
WHERE rn = 1
  AND valuenum > 0.01;