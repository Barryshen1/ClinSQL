WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'EMERGENCY'
    AND a.hadm_id IS NOT NULL
    AND a.dischtime > a.admittime
),
summary AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'DISCH HOME' THEN 'discharged home'
      WHEN discharge_location = 'HOSPICE' THEN 'hospice'
    END AS outcome,
    ROUND(AVG(los_days), 2) AS mean_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los
  FROM
    cohort
  WHERE
    hospital_expire_flag = 1
    OR discharge_location IN ('DISCH HOME', 'HOSPICE')
  GROUP BY
    outcome
),
percentile_10days AS (
  SELECT
    ROUND(AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0 END) * 100, 2) AS percentile_rank_10days
  FROM
    cohort
)
SELECT
  s.*,
  p.percentile_rank_10days
FROM
  summary s
CROSS JOIN
  percentile_10days p
ORDER BY
  CASE outcome
    WHEN 'in-hospital death' THEN 1
    WHEN 'discharged home' THEN 2
    WHEN 'hospice' THEN 3
  END;