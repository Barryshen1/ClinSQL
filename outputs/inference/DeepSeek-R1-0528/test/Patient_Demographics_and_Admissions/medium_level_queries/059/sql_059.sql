WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 75 AND 85
    AND a.dischtime >= a.admittime  -- Ensure valid LOS
),

filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE discharge_location IN ('HOME', 'HOSPICE', 'DIED')  -- Corrected 'DEAD/EXPIRED' to 'DIED'
),

by_discharge AS (
  SELECT
    discharge_location,
    COUNT(*) AS total_patients,
    COUNTIF(los_days >= 7) AS count_los_ge_7,
    COUNTIF(los_days >= 7) / COUNT(*) AS proportion
  FROM filtered_cohort
  GROUP BY discharge_location
),

overall AS (
  SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(7)] AS seventh_percentile
  FROM cohort
)

SELECT 
  discharge_location,
  total_patients,
  count_los_ge_7,
  proportion,
  NULL AS seventh_percentile
FROM by_discharge

UNION ALL

SELECT 
  'ENTIRE_COHORT' AS discharge_location,
  NULL AS total_patients,
  NULL AS count_los_ge_7,
  NULL AS proportion,
  seventh_percentile
FROM overall;