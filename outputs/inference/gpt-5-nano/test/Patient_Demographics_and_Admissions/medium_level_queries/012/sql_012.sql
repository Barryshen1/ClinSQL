WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- LOS in days (float for precision)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    -- Disposition grouping into the three requested categories
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(IFNULL(a.discharge_location, '')) LIKE '%home%' THEN 'Discharged home'
      WHEN LOWER(IFNULL(a.discharge_location, '')) LIKE '%facility%'
           OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%snf%'
           OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%rehab%'
           OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%transfer%' THEN 'To facility'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'Male'
    AND p.anchor_age BETWEEN 75 AND 85
    -- Include only records that fall into one of the three target groups
    AND (
      a.hospital_expire_flag = 1
      OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%home%'
      OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%facility%'
      OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%snf%'
      OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%rehab%'
      OR LOWER(IFNULL(a.discharge_location, '')) LIKE '%transfer%'
    )
    -- Exclude records with missing LOS or missing necessary fields
    -- (dischtime/admittime are assumed present if LOS is computed)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  discharge_group,
  COUNT(*) AS total_admissions,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS pct_los_ge_7,
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS percentile_7_day_los
FROM
  cohort
WHERE
  discharge_group IN ('Discharged home', 'To facility', 'In-hospital death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;