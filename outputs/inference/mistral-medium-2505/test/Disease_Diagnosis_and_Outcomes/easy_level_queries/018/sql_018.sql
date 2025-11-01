WITH hemorrhagic_stroke_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = 10  -- ICD-10
    AND (
      d.icd_code LIKE 'I60.%'
      OR d.icd_code LIKE 'I61.%'
      OR d.icd_code LIKE 'I62.%'
    )
    AND a.dischtime IS NOT NULL
)

SELECT
  STDDEV(length_of_stay_days) AS stddev_length_of_stay_days
FROM
  hemorrhagic_stroke_patients;