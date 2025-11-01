WITH male_80_90 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),

non_emergency_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    TIMESTAMP_DIFF(
      COALESCE(a.dischtime, a.deathtime),
      a.admittime,
      HOUR
    ) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_80_90 p ON a.subject_id = p.subject_id
  WHERE
    a.admission_type != 'EMERGENCY'
    AND a.discharge_location IN ('HOME', 'HOSPICE', 'DEAD/EXPIRED')
    AND a.admittime IS NOT NULL
    AND (a.dischtime IS NOT NULL OR a.deathtime IS NOT NULL)
)

SELECT
  discharge_location,
  COUNT(*) AS total_stays,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.25) OVER(), 2) AS p25_los,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER(), 2) AS median_los,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER(), 2) AS p75_los,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER(), 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_le_14_days
FROM
  non_emergency_admissions
GROUP BY
  discharge_location, los_days
ORDER BY
  discharge_location;