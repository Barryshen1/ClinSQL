WITH filtered AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE a.admission_type = 'EMERGENCY'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
grp AS (
  SELECT
    CASE
      WHEN (deathtime IS NOT NULL OR hospital_expire_flag = 1) THEN 'In-Hospital Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END AS discharge_group,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM filtered
  WHERE
    CASE
      WHEN (deathtime IS NOT NULL OR hospital_expire_flag = 1) THEN 'In-Hospital Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END IS NOT NULL
),
ranked AS (
  SELECT
    discharge_group,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY discharge_group ORDER BY los_days) AS rn,
    COUNT(*) OVER (PARTITION BY discharge_group) AS cnt
  FROM grp
),
q1 AS (
  SELECT discharge_group, MAX(CASE WHEN rn = CEIL(cnt * 0.25) THEN los_days END) AS q1_los_days
  FROM ranked
  GROUP BY discharge_group
),
q3 AS (
  SELECT discharge_group, MAX(CASE WHEN rn = CEIL(cnt * 0.75) THEN los_days END) AS q3_los_days
  FROM ranked
  GROUP BY discharge_group
),
median AS (
  SELECT discharge_group, MAX(CASE WHEN rn = CEIL(cnt * 0.5) THEN los_days END) AS median_los_days
  FROM ranked
  GROUP BY discharge_group
)
SELECT
  m.discharge_group AS discharge_group,
  m.median_los_days AS median_los_days,
  q1.q1_los_days AS q1_los_days,
  q3.q3_los_days AS q3_los_days,
  (q3.q3_los_days - q1.q1_los_days) AS iqr_los_days
FROM median m
LEFT JOIN q1 ON m.discharge_group = q1.discharge_group
LEFT JOIN q3 ON m.discharge_group = q3.discharge_group
ORDER BY discharge_group;