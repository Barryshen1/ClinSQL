WITH dialysis_patients AS (
  -- Identify dialysis patients using ICD-9/10 codes for dialysis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code IN (
    'V4511', 'V560', 'V561', 'V562', 'V568', 'V569', 'Z992'  -- Dialysis-related ICD codes
  )
  UNION DISTINCT
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE p.icd_code = '3995'  -- Hemodialysis procedure code
),

patient_demographics AS (
  -- Filter for male patients aged 44-54
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),

admissions_with_los AS (
  -- Calculate LOS for each admission
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN dialysis_patients dp ON a.hadm_id = dp.hadm_id
  JOIN patient_demographics pd ON a.subject_id = pd.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)

-- Compute the standard deviation of LOS
SELECT
  STDDEV(length_of_stay_days) AS sd_length_of_stay_days
FROM admissions_with_los;