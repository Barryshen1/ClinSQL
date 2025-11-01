SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND a.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-2]'))
    )
) AS cohort;