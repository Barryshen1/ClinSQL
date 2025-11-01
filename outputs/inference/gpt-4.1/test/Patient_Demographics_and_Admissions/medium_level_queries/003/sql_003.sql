WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_calc AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM cohort
  WHERE
    DATETIME_DIFF(dischtime, admittime, DAY) > 0
),
grouped AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS disposition_group
  FROM los_calc
)
SELECT
  disposition_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los,
  -- Get percentiles using APPROX_QUANTILES
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_14
FROM
  grouped
WHERE
  disposition_group IS NOT NULL
GROUP BY
  disposition_group
ORDER BY
  disposition_group;