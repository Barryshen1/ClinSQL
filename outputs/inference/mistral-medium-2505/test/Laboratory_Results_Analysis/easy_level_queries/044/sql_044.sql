WITH
-- Get ischemic stroke ICD codes
stroke_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '433.%' AND icd_code LIKE '%.1')
    OR (icd_version = 9 AND icd_code LIKE '434.%' AND icd_code LIKE '%.1')
    OR (icd_version = 9 AND icd_code = '436')
    OR (icd_version = 10 AND icd_code LIKE 'I63.%')
),

-- Get male patients aged 94 with ischemic stroke admissions
stroke_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN stroke_codes sc ON d.icd_code = sc.icd_code AND d.icd_version =
    CASE
      WHEN sc.icd_code LIKE '433.%' OR sc.icd_code LIKE '434.%' OR sc.icd_code = '436' THEN 9
      WHEN sc.icd_code LIKE 'I63.%' THEN 10
    END
  WHERE p.gender = 'M' AND p.anchor_age = 94
),

-- Get glucose measurements on discharge day
glucose_on_discharge AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    le.valuenum AS glucose_value,
    le.charttime
  FROM stroke_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sp.subject_id = le.subject_id AND sp.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE
    dli.label LIKE '%Glucose%' AND
    DATE(le.charttime) = DATE(sp.dischtime) AND
    le.valuenum IS NOT NULL
),

-- Get most recent glucose measurement per patient on discharge day
latest_glucose AS (
  SELECT
    subject_id,
    hadm_id,
    glucose_value,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime DESC) AS rn
  FROM glucose_on_discharge
)

-- Calculate IQR of glucose values
SELECT
  PERCENTILE_CONT(glucose_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(glucose_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(glucose_value, 0.75) OVER() - PERCENTILE_CONT(glucose_value, 0.25) OVER() AS iqr
FROM latest_glucose
WHERE rn = 1
LIMIT 1;