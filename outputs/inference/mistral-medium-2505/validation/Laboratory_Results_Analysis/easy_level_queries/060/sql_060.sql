WITH
-- Get pneumonia ICD codes (J12-J18, J69.0)
pneumonia_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND (
      icd_code LIKE 'J12%' OR
      icd_code LIKE 'J13%' OR
      icd_code LIKE 'J14%' OR
      icd_code LIKE 'J15%' OR
      icd_code LIKE 'J16%' OR
      icd_code LIKE 'J17%' OR
      icd_code LIKE 'J18%' OR
      icd_code = 'J69.0'
    )
),

-- Get male patients aged 67
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age = 67
),

-- Get admissions with pneumonia diagnosis
pneumonia_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN pneumonia_icd p
    ON d.icd_code = p.icd_code AND d.icd_version = 10
  WHERE a.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Get serum glucose measurements in first 24h
serum_glucose AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN pneumonia_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE d.label = 'Glucose'
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL
),

-- Calculate mean serum glucose per admission
mean_glucose_per_admission AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS mean_glucose
  FROM serum_glucose
  GROUP BY hadm_id
)

-- Calculate 75th percentile of mean glucose
SELECT
  PERCENTILE_CONT(mean_glucose, 0.75) OVER() AS percentile_75_mean_glucose
FROM mean_glucose_per_admission
LIMIT 1;