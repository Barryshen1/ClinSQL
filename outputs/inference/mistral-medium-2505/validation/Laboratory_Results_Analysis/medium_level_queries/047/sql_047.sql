WITH
-- Get female patients aged 67-77
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),

-- Get admissions with ACS diagnosis (ICD-10 codes I20-I25)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code LIKE 'I2%'
    AND a.subject_id IN (SELECT subject_id FROM female_patients)
),

-- Get first troponin T measurement for each admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    (d.label LIKE '%Troponin T%' OR d.loinc_code = '10839-9')
    AND l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND l.valuenum IS NOT NULL
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(troponin_value), 4) AS mean_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.5), 4) AS median_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.25), 4) AS q1_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.75), 4) AS q3_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.75) - PERCENTILE_CONT(troponin_value, 0.25), 4) AS iqr_troponin
FROM
  first_troponin
WHERE
  rn = 1
  AND troponin_value > 0.03  -- 99th percentile threshold;