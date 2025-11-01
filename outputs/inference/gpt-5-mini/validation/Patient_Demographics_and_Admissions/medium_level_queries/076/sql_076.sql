SELECT
  outcome,
  n_admissions,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(q[OFFSET(50)], 2) AS p50_los_days,
  ROUND(q[OFFSET(75)], 2) AS p75_los_days,
  ROUND(q[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100.0 * SAFE_DIVIDE(cnt_le_5, n_admissions), 2) AS pct_rank_5day
FROM (
  SELECT
    CASE WHEN hospital_expire_flag = 1 THEN 'died_in_hospital' ELSE 'discharged_alive' END AS outcome,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100) AS q,
    SUM(IF(los_days <= 5, 1, 0)) AS cnt_le_5
  FROM (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.hospital_expire_flag,
      -- LOS in fractional days
      SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 83 AND 93
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
  ) admissions_with_los
  WHERE los_days IS NOT NULL
    AND los_days >= 0
  GROUP BY outcome
)
ORDER BY outcome;