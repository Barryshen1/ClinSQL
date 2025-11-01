WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_category
  FROM
    cohort
)
SELECT
  discharge_category,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS percentile_90,
  AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100 AS pct_los_le_10_days
FROM
  discharge_groups
WHERE
  discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;