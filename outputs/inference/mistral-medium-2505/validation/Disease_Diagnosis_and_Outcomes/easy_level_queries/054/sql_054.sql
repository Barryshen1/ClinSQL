WITH hemorrhagic_stroke_patients AS (
  -- Get patients with primary hemorrhagic stroke diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- Males aged 51-61 at admission (anchor_age is age at first admission)
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    -- Primary diagnosis (seq_num = 1) of hemorrhagic stroke
    AND d.seq_num = 1
    AND (
      -- ICD-10 codes for hemorrhagic stroke (I61.*)
      (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
      OR
      -- ICD-9 codes for hemorrhagic stroke (431.*)
      (d.icd_version = 9 AND d.icd_code LIKE '431%')
    )
    -- Ensure discharge time is available
    AND a.dischtime IS NOT NULL
)

-- Calculate standard deviation of length of stay
SELECT
  STDDEV(length_of_stay_days) AS stddev_length_of_stay_days
FROM
  hemorrhagic_stroke_patients;