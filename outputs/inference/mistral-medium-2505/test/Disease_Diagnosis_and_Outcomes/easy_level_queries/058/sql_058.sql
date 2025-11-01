WITH hemorrhagic_stroke_patients AS (
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
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '430.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I60.%')
    )
)

SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS percentile_75_los
FROM
  hemorrhagic_stroke_patients
LIMIT 1;