WITH ischemic_stroke_patients AS (
  -- Get patients with primary ischemic stroke diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    -- Male patients aged 84-94
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    -- Primary diagnosis (seq_num = 1) and ischemic stroke (ICD-10: I63.* or similar)
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND di.icd_code LIKE 'I63.%')
      OR (d.icd_version = 9 AND di.icd_code IN ('434.91', '434.11', '434.01')) -- Example ICD-9 codes for ischemic stroke
    )
    -- Ensure discharge time is valid (handle NULLs)
    AND a.dischtime IS NOT NULL
)

-- Calculate maximum LOS
SELECT
  MAX(los_days) AS max_los_days
FROM
  ischemic_stroke_patients;