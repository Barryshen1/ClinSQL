WITH relevant_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_code = 'I63' -- Primary ischemic stroke code
    AND d.seq_num = 1 -- Primary diagnosis
)
SELECT
  PERCENTILE_CONT(0.25, TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS q1,
  PERCENTILE_CONT(0.75, TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS q3
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  relevant_patients AS rp
  ON a.subject_id = rp.subject_id
WHERE
  a.hospital_expire_flag = 0;