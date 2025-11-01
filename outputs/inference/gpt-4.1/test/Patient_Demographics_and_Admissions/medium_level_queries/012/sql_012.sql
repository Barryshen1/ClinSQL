WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'HOME') THEN 'Home'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'SNF|REHAB|SKILLED NURSING|NURSING HOME|LONG TERM CARE|FACILITY|LTAC|LTACH|ASSISTED LIVING|HOSPICE') THEN 'Facility'
      ELSE NULL
    END AS discharge_category,
    CASE WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 7 THEN 1 ELSE 0 END AS los_ge_7d
  FROM base
),
filtered AS (
  SELECT
    *
  FROM discharge_categorized
  WHERE discharge_category IS NOT NULL
)
-- Aggregate results
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  ROUND(SUM(los_ge_7d) / COUNT(*), 3) AS proportion_los_ge_7d,
  -- Percentile rank: proportion of admissions with LOS <= 7 days
  ROUND(
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*),
    3
  ) AS percentile_rank_7d_los
FROM
  filtered
GROUP BY
  discharge_category
ORDER BY
  discharge_category;