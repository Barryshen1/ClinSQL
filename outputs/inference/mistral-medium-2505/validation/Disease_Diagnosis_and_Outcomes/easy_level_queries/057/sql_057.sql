WITH cap_patients AS (
  -- Identify women aged 88-98 with primary CAP diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for CAP (e.g., 486)
      (d.icd_version = 9 AND d.icd_code IN ('486', '485', '4828', '4823', '4824', '4829'))
      OR
      -- ICD-10 codes for CAP (e.g., J18.9)
      (d.icd_version = 10 AND d.icd_code IN ('J189', 'J181', 'J180', 'J188', 'J159', 'J158'))
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)

-- Calculate minimum LOS
SELECT
  MIN(los_days) AS min_hospital_los_days
FROM
  cap_patients;