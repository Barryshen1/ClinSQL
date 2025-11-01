WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMER'
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    cohort
)
SELECT
  discharge_category,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(CASE WHEN los_days < 5 THEN 1 ELSE 0 END) * 100 AS pct_los_lt_5_days
FROM
  discharge_groups
WHERE
  discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;