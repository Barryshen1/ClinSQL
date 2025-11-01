WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Calculate age at admission
    p.anchor_age - (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in minutes for precision
    DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) AS los_minutes,
    -- Define discharge groups
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 52 AND 62
)
-- Overall LOS stats (mean ± SD) and percentile rank by discharge group
SELECT
  'Overall' AS category,
  NULL AS discharge_group,
  AVG(los_minutes) / (24 * 60) AS mean_los,  -- Convert minutes to days
  STDDEV_POP(los_minutes) / (24 * 60) AS sd_los,  -- Convert minutes to days
  NULL AS percentile_rank_5day
FROM filtered_cohort
UNION ALL
SELECT
  'By Discharge Group' AS category,
  discharge_group,
  NULL AS mean_los,
  NULL AS sd_los,
  -- Percentile rank for 5 days (7200 minutes)
  (COUNTIF(los_minutes < 7200) + 0.5 * COUNTIF(los_minutes = 7200)) / COUNT(*) AS percentile_rank_5day
FROM filtered_cohort
GROUP BY discharge_group;