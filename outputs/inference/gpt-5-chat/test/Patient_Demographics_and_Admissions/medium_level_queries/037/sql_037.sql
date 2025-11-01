WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND UPPER(a.admission_type) != 'EMERGENCY'
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    ELSE 'Discharged alive'
  END AS discharge_status,
  COUNT(*) AS n_admissions,
  -- Percentiles via APPROX_QUANTILES
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  SAFE_DIVIDE(SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END), COUNT(*)) AS pct_rank_7d
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  discharge_status;