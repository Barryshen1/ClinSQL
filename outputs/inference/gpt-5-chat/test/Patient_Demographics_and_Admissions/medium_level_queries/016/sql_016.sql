WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    -- length of stay in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'hospice'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'home'
      ELSE 'other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    (SELECT DISTINCT hadm_id
     FROM `physionet-data.mimiciv_3_1_icu.icustays`) icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND icu.hadm_id IS NULL  -- exclude ICU admissions
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
filtered AS (
  SELECT *
  FROM cohort
  WHERE discharge_group IN ('home', 'hospice', 'death')
),
stats AS (
  SELECT
    discharge_group,
    PERCENTILE_CONT(los_days, 0.5) OVER w AS p50,
    PERCENTILE_CONT(los_days, 0.75) OVER w AS p75,
    PERCENTILE_CONT(los_days, 0.90) OVER w AS p90,
    PERCENTILE_CONT(los_days, 0.95) OVER w AS p95,
    SAFE_DIVIDE(
      SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) OVER w,
      COUNT(*) OVER w
    ) AS percentile_rank_7day
  FROM filtered
  WINDOW w AS (PARTITION BY discharge_group)
)
SELECT DISTINCT
  discharge_group,
  p50,
  p75,
  p90,
  p95,
  percentile_rank_7day
FROM stats
ORDER BY discharge_group;