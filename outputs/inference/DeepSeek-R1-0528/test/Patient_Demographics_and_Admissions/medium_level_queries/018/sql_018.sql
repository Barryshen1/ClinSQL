WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Define discharge categories (Death takes precedence)
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'Home' THEN 'Home'
      WHEN a.discharge_location IN (
        'Skilled Nursing Facility', 'Rehabilitation', 'Hospice', 'Other Facility'
      ) THEN 'Facility'
    END AS discharge_category,
    -- Calculate Length of Stay (LOS) in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'Transfer from another hospital'
),
filtered AS (
  -- Exclude admissions not fitting the 3 discharge categories
  SELECT *
  FROM base
  WHERE discharge_category IS NOT NULL
),
stats AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_admissions,
    COUNTIF(los_days <= 10) AS admissions_under_10_days,
    APPROX_QUANTILES(los_days, 4) AS quartiles  -- [min, Q1, median, Q3, max]
  FROM filtered
  GROUP BY discharge_category
)
SELECT
  discharge_category,
  total_admissions,
  quartiles[OFFSET(1)] AS q1,       -- 25th percentile
  quartiles[OFFSET(2)] AS median,   -- 50th percentile
  quartiles[OFFSET(3)] AS q3,       -- 75th percentile
  ROUND(admissions_under_10_days * 100.0 / total_admissions, 2) AS pct_under_10_days
FROM stats
ORDER BY discharge_category;