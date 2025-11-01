WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND (
      UPPER(a.admission_location) LIKE 'EMER%'
      OR UPPER(a.admission_location) LIKE '%ER%'
    )
),
filtered_los AS (
  SELECT *
  FROM patient_los
  WHERE age_at_admission BETWEEN 43 AND 53
    AND los_days >= 0
),
categorized_los AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_group
  FROM filtered_los
),
stats_per_group AS (
  SELECT
    discharge_group,
    los_days,
    PERCENTILE_CONT(los_days, 0.25) OVER (PARTITION BY discharge_group) AS q1,
    PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY discharge_group) AS median_los,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_group) AS q3,
    -- Compute cumulative distribution: fraction of rows <= current row
    CUME_DIST() OVER (PARTITION BY discharge_group ORDER BY los_days) AS cume_dist
  FROM categorized_los
)
SELECT
  discharge_group,
  ROUND(median_los, 2) AS median_los_days,
  ROUND(q1, 2) AS q1_los_days,
  ROUND(q3, 2) AS q3_los_days,
  -- Format IQR as "Q1 - Q3"
  CONCAT(ROUND(q1, 2), ' - ', ROUND(q3, 2)) AS iqr_los_days,
  -- Percentile rank of 14-day stay: max cume_dist for los_days <= 14
  ROUND(MAX(CASE WHEN los_days <= 14 THEN cume_dist END), 4) AS percentile_rank_of_14day
FROM stats_per_group
GROUP BY discharge_group, median_los, q1, q3
ORDER BY discharge_group;