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
    p.gender = 'F'
    AND a.admission_type = 'EMER'
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
),
discharge_groups AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    cohort
)
SELECT
  discharge_category,
  COUNT(*) AS n,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_category) AS median_los,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_category) -
    PERCENTILE_CONT(los_days, 0.25) OVER (PARTITION BY discharge_category) AS iqr_los
FROM
  discharge_groups
WHERE
  discharge_category IN ('Home', 'Hospice', 'Died in Hospital')
GROUP BY
  discharge_category, los_days
ORDER BY
  discharge_category;