SELECT
  AVG(LOS) AS avg_hospital_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND d.seq_num = 1
    AND (
      -- ICD-9 heart failure: 428.x
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
      -- ICD-10 heart failure: I50.x
      OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
);