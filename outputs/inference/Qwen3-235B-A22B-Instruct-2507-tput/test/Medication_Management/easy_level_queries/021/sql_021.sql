SELECT
  APPROX_QUANTILES(duration_hours, 1000)[OFFSET(750)] - APPROX_QUANTILES(duration_hours, 1000)[OFFSET(250)] AS iqr_duration_hours
FROM (
  SELECT
    p.subject_id,
    p.pharmacy_id,
    DATETIME_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  WHERE
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND p.dose_val_rx IS NOT NULL
    AND REGEXP_CONTAINS(p.dose_val_rx, r'^[0-9]+\.?[0-9]*$')  -- Ensures numeric-only string (e.g., "40", "80", "40.0")
    AND CAST(p.dose_val_rx AS FLOAT64) >= 40
    AND CAST(p.dose_val_rx AS FLOAT64) <= 80
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.hadm_id IS NOT NULL
    AND pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM p.starttime) - pat.anchor_year)) >= 75
    AND (pat.anchor_age + (EXTRACT(YEAR FROM p.starttime) - pat.anchor_year)) <= 85
)
WHERE
  duration_hours > 0;