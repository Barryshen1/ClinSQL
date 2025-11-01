WITH cohort AS (
  SELECT
    a.hadm_id,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      ELSE 'alive'
    END AS discharged_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  discharged_status,
  APPROX_QUANTILES(los, 100)[OFFSET(50)]  AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)]  AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)]  AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)]  AS p95,
  ROUND(
    100.0 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS pct_rank_7_days
FROM
  cohort
GROUP BY
  discharged_status
ORDER BY
  discharged_status;