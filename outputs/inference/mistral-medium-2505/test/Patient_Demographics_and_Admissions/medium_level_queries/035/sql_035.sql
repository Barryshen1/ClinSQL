WITH female_ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age,
    -- Calculate LOS in days
    CASE
      WHEN a.hospital_expire_flag = 1 AND a.deathtime IS NOT NULL
      THEN DATETIME_DIFF(a.deathtime, a.admittime, HOUR)/24
      ELSE DATETIME_DIFF(
        CASE WHEN a.dischtime IS NULL THEN CURRENT_DATETIME() ELSE a.dischtime END,
        a.admittime,
        HOUR)/24
    END AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND a.admittime IS NOT NULL
    AND (a.dischtime IS NOT NULL OR a.deathtime IS NOT NULL)
),

discharge_categories AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM
    female_ed_admissions
),

stats_by_category AS (
  SELECT
    discharge_category,
    COUNT(*) AS patient_count,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS median_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(0)] AS q1_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS q3_los,
    -- Calculate percentile rank for 14-day stay
    (SELECT COUNT(*) FROM discharge_categories d
     WHERE d.discharge_category = s.discharge_category AND d.los_days <= 14) /
    COUNT(*) AS percentile_rank_14day
  FROM
    discharge_categories s
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  patient_count,
  median_los,
  q1_los,
  q3_los,
  q1_los AS iqr_lower,
  q3_los AS iqr_upper,
  ROUND(percentile_rank_14day * 100, 2) AS percentile_rank_14day
FROM
  stats_by_category
ORDER BY
  discharge_category;