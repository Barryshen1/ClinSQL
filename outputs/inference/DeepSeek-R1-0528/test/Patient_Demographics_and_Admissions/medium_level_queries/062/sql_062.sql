WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Define discharge groups
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL', 'CHRONIC/LONG TERM ACUTE CARE'
      ) THEN 'SNF/rehab/LTACH'
      ELSE NULL  -- Exclude other groups
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Filter age 64-74 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
    -- Pre-filter valid discharge groups
    AND (
      a.hospital_expire_flag = 1
      OR a.discharge_location = 'HOME'
      OR a.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL', 'CHRONIC/LONG TERM ACUTE CARE'
      )
    )
)

SELECT
  discharge_group,
  COUNT(*) AS total_count,
  -- Count admissions with LOS >=7 days
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_7day,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS proportion_7day,
  -- Count admissions with LOS >=14 days
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS count_14day,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS proportion_14day
FROM
  cohort
WHERE
  discharge_group IS NOT NULL  -- Ensure only defined groups
GROUP BY
  discharge_group
ORDER BY
  discharge_group;