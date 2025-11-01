WITH
-- Get female patients aged 84-94
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 84 AND 94
),

-- Get admissions with ACS diagnosis
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- ICD-10 codes for ACS (I20-I25)
      (d.icd_version = 10 AND di.icd_code BETWEEN 'I20' AND 'I25')
      OR
      -- ICD-9 codes for ACS (410-414)
      (d.icd_version = 9 AND di.icd_code BETWEEN '410' AND '414')
    )
),

-- Get Troponin I measurements (itemid 50912 for Troponin I in MIMIC-IV)
troponin_measurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE
    l.subject_id IN (SELECT subject_id FROM female_patients)
    AND l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND dl.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
),

-- Get first Troponin I measurement per admission that exceeds 99th percentile ULN (0.04 ng/mL)
initial_high_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    CAST(troponin_value AS FLOAT64) AS troponin_value
  FROM
    troponin_measurements
  WHERE
    measurement_rank = 1
    AND troponin_value > 0.04  -- 99th percentile ULN for Troponin I
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS q1_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS q3_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] - APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS iqr_troponin
FROM
  initial_high_troponin;