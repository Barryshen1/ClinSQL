WITH sepsis_patients AS (
  -- Identify female patients aged 67-77
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS length_of_stay_days,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    -- Filter for primary diagnosis (seq_num = 1) and sepsis/septic shock ICD codes
    AND d.seq_num = 1
    AND (
      -- ICD-9 codes for sepsis/septic shock
      (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92', '785.52'))
      OR
      -- ICD-10 codes for sepsis/septic shock
      (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'R65.21', 'R65.20', 'R65.22'))
    )
)

-- Get the maximum length of stay
SELECT
  MAX(length_of_stay_days) AS max_length_of_stay_days
FROM
  sepsis_patients;