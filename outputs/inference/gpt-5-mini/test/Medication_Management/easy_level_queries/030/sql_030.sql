WITH cohort_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, MINUTE) AS duration_minutes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Ensure prescription started during the hospital admission
    AND pr.starttime >= a.admittime
    AND pr.starttime <= a.dischtime
    -- match drug name containing "amiodarone" (case-insensitive)
    AND LOWER(COALESCE(pr.drug, '')) LIKE '%amiodarone%'
    -- positive duration only
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, MINUTE) > 0
)
SELECT
  -- 25th percentile duration (approx) in minutes converted to hours and days
  CAST(APPROX_QUANTILES(duration_minutes, 100)[OFFSET(25)] AS FLOAT64) / 60.0 AS pct25_hours,
  CAST(APPROX_QUANTILES(duration_minutes, 100)[OFFSET(25)] AS FLOAT64) / (60.0 * 24.0) AS pct25_days,
  COUNT(*) AS n_prescriptions
FROM cohort_prescriptions;