WITH female_age_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_age_filtered f
    ON a.subject_id = f.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
quartiles AS (
  SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS q3
  FROM first_admissions
)
SELECT DISTINCT
  q3 - q1 AS iqr_los_days
FROM quartiles;