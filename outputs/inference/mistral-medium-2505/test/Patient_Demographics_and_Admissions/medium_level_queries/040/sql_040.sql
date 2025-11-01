WITH surgical_females_70_80 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type = 'SURGICAL'
    AND a.dischtime IS NOT NULL
),

discharge_categories AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'Facility'
      ELSE 'Other/Unknown'
    END AS discharge_category
  FROM
    surgical_females_70_80
),

los_counts AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge14
  FROM
    discharge_categories
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  total_patients,
  ROUND(los_ge7 / total_patients * 100, 2) AS percent_los_ge7,
  ROUND(los_ge14 / total_patients * 100, 2) AS percent_los_ge14
FROM
  los_counts
ORDER BY
  discharge_category;