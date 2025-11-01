WITH amio_raw AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    LOWER(p.drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
    AND p.subject_id = a.subject_id
  WHERE
    LOWER(p.drug) LIKE '%amiodarone%'
    AND pt.gender = 'M'
    AND pt.anchor_age BETWEEN 62 AND 72
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    -- ensure the prescription occurs during the hospital admission
    AND p.starttime BETWEEN a.admittime AND a.dischtime
),

single_admissions AS (
  -- admissions with exactly one amiodarone prescription record
  SELECT hadm_id
  FROM amio_raw
  GROUP BY hadm_id
  HAVING COUNT(*) = 1
),

durations AS (
  SELECT
    TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0 AS duration_days
  FROM amio_raw
  WHERE hadm_id IN (SELECT hadm_id FROM single_admissions)
)

SELECT
  SAFE_CAST(quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS FLOAT64) AS iqr_days,
  SAFE_CAST(quantiles[OFFSET(25)] AS FLOAT64) AS q1_days,
  SAFE_CAST(quantiles[OFFSET(75)] AS FLOAT64) AS q3_days,
  cnt AS n_prescriptions
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS quantiles,
    COUNT(*) AS cnt
  FROM durations
);