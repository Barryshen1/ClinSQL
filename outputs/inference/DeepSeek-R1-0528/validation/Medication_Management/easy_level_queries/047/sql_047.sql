WITH filtered_prescriptions AS (
  SELECT
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    -- Female patients
    pt.gender = 'F'
    -- Age 60-70 at admission
    AND pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year) BETWEEN 60 AND 70
    -- Atorvastatin filter (case-insensitive)
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    -- Dose 40 mg or 80 mg (extract leading numeric part)
    AND SAFE_CAST(REGEXP_EXTRACT(p.dose_val_rx, r'^(\d+)') AS INT64) IN (40, 80)
    -- Unit is 'mg' (case-insensitive)
    AND LOWER(p.dose_unit_rx) = 'mg'
    -- Valid start/stop times and non-negative duration
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr
FROM filtered_prescriptions;