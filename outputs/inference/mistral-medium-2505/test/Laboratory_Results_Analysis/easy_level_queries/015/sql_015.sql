WITH
-- Get female patients
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),

-- Get pneumonia admissions (ICD-10: J18.9 or ICD-9: 486)
pneumonia_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('J18.9', '486')  -- Pneumonia ICD codes
    AND d.seq_num = 1  -- Primary diagnosis
),

-- Get creatinine itemid (e.g., 50912 for serum creatinine)
creatinine_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Creatinine' AND fluid = 'Blood'  -- Serum creatinine
),

-- Get creatinine measurements for female pneumonia patients
creatinine_measurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN female_patients f ON l.subject_id = f.subject_id
  JOIN pneumonia_admissions p ON l.subject_id = p.subject_id AND l.hadm_id = p.hadm_id
  JOIN creatinine_itemid c ON l.itemid = c.itemid
  WHERE l.valuenum IS NOT NULL  -- Exclude null values
),

-- Calculate 24-hour average creatinine per patient
avg_creatinine_24h AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_TRUNC(charttime, DAY) AS day,
    AVG(valuenum) AS avg_creatinine
  FROM creatinine_measurements
  GROUP BY subject_id, hadm_id, day
)

-- Find the minimum 24-hour average creatinine
SELECT
  MIN(avg_creatinine) AS min_avg_creatinine_24h
FROM avg_creatinine_24h;