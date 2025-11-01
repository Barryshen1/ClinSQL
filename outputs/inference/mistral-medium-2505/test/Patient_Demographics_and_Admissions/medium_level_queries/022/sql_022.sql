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
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(a.admission_location) LIKE '%hospital%'
    AND a.dischtime IS NOT NULL
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
  COUNT(*) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.25) OVER(), 2) AS percentile_25,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER(), 2) AS percentile_50,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER(), 2) AS percentile_75,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER(), 2) AS percentile_90,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_leq_10_days
FROM
  discharge_categories
GROUP BY
  discharge_category, los_days
ORDER BY
  discharge_category;