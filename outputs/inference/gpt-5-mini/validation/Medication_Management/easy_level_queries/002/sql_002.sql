WITH cohort_presc AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND), 86400.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND p.hadm_id = a.hadm_id
  WHERE LOWER(COALESCE(p.drug, '')) LIKE '%amiodarone%'
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) > 0
    AND p.starttime >= a.admittime
    AND p.starttime <= a.dischtime
)

SELECT
  SAFE_CAST(quantiles[OFFSET(1)] AS FLOAT64) AS q1_days,
  SAFE_CAST(quantiles[OFFSET(3)] AS FLOAT64) AS q3_days,
  SAFE_CAST(quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS FLOAT64) AS iqr_days,
  total_count AS n_prescriptions
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles,
    COUNT(*) AS total_count
  FROM cohort_presc
);