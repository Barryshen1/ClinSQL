WITH ischemic_stroke_patients AS (
  -- Identify female patients aged 71-81 with primary ischemic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for ischemic stroke
      (d.icd_version = 9 AND d.icd_code LIKE '433.%' AND d.icd_code LIKE '%.x1')
      OR (d.icd_version = 9 AND d.icd_code LIKE '434.%' AND d.icd_code LIKE '%.x1')
      OR (d.icd_version = 9 AND d.icd_code = '436')
      -- ICD-10 codes for ischemic stroke
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63.%')
    )
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

-- Calculate IQR of LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr
FROM
  ischemic_stroke_patients
LIMIT 1;