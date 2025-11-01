WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND p.anchor_age BETWEEN 89 AND 99
),

discharge_categories AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    patient_admissions
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER(), 2) AS median_los,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER(), 2) AS p75_los,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER(), 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days < 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_lt_5_days
FROM
  discharge_categories
GROUP BY
  discharge_category, los_days
ORDER BY
  discharge_category;