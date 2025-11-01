WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    (p.anchor_year - p.anchor_age) AS birth_year,
    SAFE_CAST(EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS INT64) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND SAFE_CAST(EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS INT64) BETWEEN 60 AND 70
),
prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    DATEDIFF(stoptime, starttime) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug = 'atorvastatin'
    AND dose_unit_rx = 'mg'
    AND dose_val_rx BETWEEN 40 AND 80
    AND starttime IS NOT NULL
    AND stoptime IS NOT NULL
    AND DATEDIFF(stoptime, starttime) >= 0
),
combined AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    p.duration_days
  FROM eligible_patients e
  INNER JOIN prescriptions p
    ON e.subject_id = p.subject_id
    AND e.hadm_id = p.hadm_id
),
stats AS (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM combined
)
SELECT
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days
FROM stats;