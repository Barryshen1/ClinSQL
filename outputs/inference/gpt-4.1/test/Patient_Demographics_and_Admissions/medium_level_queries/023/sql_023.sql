WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days
    SAFE_CAST(DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
      OR LOWER(a.admission_location) LIKE '%er%'
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
, discharge_categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%nursing%'
        OR LOWER(discharge_location) LIKE '%skilled%'
        OR LOWER(discharge_location) LIKE '%facility%'
        OR LOWER(discharge_location) LIKE '%hospice%'
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM cohort
)
, filtered AS (
  SELECT *
  FROM discharge_categorized
  WHERE discharge_category IN ('Home', 'Facility', 'In-hospital death')
)
, summary AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    COUNTIF(los_days >= 7) AS los_ge_7_count,
    SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS los_ge_7_proportion
  FROM filtered
  GROUP BY discharge_category
)
, percentile_10day AS (
  SELECT
    discharge_category,
    SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(*)) AS los_10day_percentile
  FROM filtered
  GROUP BY discharge_category
)
SELECT
  s.discharge_category,
  s.total_patients,
  s.los_ge_7_count,
  s.los_ge_7_proportion,
  p.los_10day_percentile
FROM
  summary s
  JOIN percentile_10day p
    ON s.discharge_category = p.discharge_category
ORDER BY
  s.discharge_category;