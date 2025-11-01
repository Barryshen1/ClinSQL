WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.deathtime) AS discharge_time,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days
    DATETIME_DIFF(COALESCE(a.dischtime, a.deathtime), a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMERGENCY'
    AND COALESCE(a.dischtime, a.deathtime) IS NOT NULL
    AND a.admittime IS NOT NULL
)

, discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)

SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los),2) AS mean_los,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
  APPROX_QUANTILES(los, 10)[OFFSET(9)] AS p90_los,
  ROUND(100 * COUNTIF(los < 5) / COUNT(*), 1) AS pct_los_lt_5_days
FROM
  discharge_groups
WHERE
  discharge_group IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;