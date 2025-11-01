SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(CAST(a.dischtime AS TIMESTAMP), CAST(a.admittime AS TIMESTAMP), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = '10' AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
);