WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND d.icd_code IN (
      'N17.0', 'N17.1', 'N17.2', 'N17.3', 'N17.4', 'N17.5', 'N17.6', 'N17.7', 'N17.8', 'N17.9'
    )
    AND a.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM
  eligible_admissions;