WITH filtered_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    (EXTRACT(YEAR FROM p.starttime) - pat.anchor_year) + pat.anchor_age AS age_at_prescription,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND p.dose_unit_rx = 'mg'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.stoptime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM filtered_prescriptions
WHERE age_at_prescription BETWEEN 75 AND 85;