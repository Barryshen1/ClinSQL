WITH sepsis_admissions AS (
  -- Get admissions for female patients aged 40-50 with primary sepsis/septic shock
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
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
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for sepsis/septic shock
      (d.icd_version = 9 AND d.icd_code IN ('99591', '78552'))
      OR
      -- ICD-10 codes for sepsis/septic shock
      (d.icd_version = 10 AND d.icd_code IN ('R6520', 'R6521', 'A419', 'A4151', 'A4152'))
    )
    AND a.dischtime IS NOT NULL
)

-- Calculate IQR for hospital LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr
FROM
  sepsis_admissions
LIMIT 1;