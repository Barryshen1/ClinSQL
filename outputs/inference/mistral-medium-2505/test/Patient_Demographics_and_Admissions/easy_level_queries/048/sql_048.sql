WITH
-- Get heart failure ICD codes (both ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50%'  -- ICD-10 heart failure
     OR icd_code LIKE '428%'  -- ICD-9 heart failure
),

-- Get patients with heart failure
hf_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
),

-- Get first admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_patients p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL  -- Only completed admissions
)

-- Final calculation of IQR for LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr
FROM first_admissions
WHERE admission_rank = 1  -- Only first admission
  AND subject_id IN (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 79 AND 89
  )
LIMIT 1;  -- Since we're calculating percentiles over the entire result set;