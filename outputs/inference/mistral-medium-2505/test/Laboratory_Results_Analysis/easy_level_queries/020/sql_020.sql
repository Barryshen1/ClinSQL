WITH
-- Get male patients aged 49
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age = 49
),

-- Get heart failure hospitalizations
heart_failure_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN male_patients mp ON a.subject_id = mp.subject_id
  WHERE d.icd_code IN (
    -- ICD-9 codes for heart failure
    '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289',
    -- ICD-10 codes for heart failure
    'I501', 'I5020', 'I5021', 'I5022', 'I5023', 'I5030', 'I5031', 'I5032', 'I5033', 'I5034', 'I5040', 'I5041', 'I5042', 'I5043', 'I5044', 'I509'
  )
),

-- Get hemoglobin measurements during these hospitalizations
hemoglobin_measurements AS (
  SELECT
    hfa.hadm_id,
    le.valuenum AS hemoglobin_value,
    le.charttime
  FROM heart_failure_admissions hfa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON hfa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE dli.label = 'Hemoglobin'
    AND le.charttime BETWEEN hfa.admittime AND hfa.dischtime
    AND le.valuenum IS NOT NULL
),

-- Find the nadir (minimum) hemoglobin for each hospitalization
nadir_hemoglobin AS (
  SELECT
    hadm_id,
    MIN(hemoglobin_value) AS nadir_hemoglobin
  FROM hemoglobin_measurements
  GROUP BY hadm_id
)

-- Calculate the 75th percentile of nadir hemoglobin values
SELECT
  PERCENTILE_CONT(nadir_hemoglobin, 0.75) OVER() AS percentile_75_nadir_hemoglobin
FROM nadir_hemoglobin
LIMIT 1;