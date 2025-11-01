WITH cohort_los AS (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.icd_version = 10
    AND SUBSTR(d.icd_code, 1, 3) IN ('I60', 'I61', 'I62')
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los_days
FROM
  cohort_los;