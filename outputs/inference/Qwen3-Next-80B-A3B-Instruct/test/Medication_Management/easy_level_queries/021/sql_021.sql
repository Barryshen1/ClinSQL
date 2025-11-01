WITH atorvastatin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.dose_val_rx,
    p.dose_unit_rx,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients pt
    ON p.subject_id = pt.subject_id
  WHERE
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND REGEXP_CONTAINS(p.dose_val_rx, r'^[0-9]+\.?[0-9]*$')  -- Ensure numeric string
    AND CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND LOWER(TRIM(p.dose_unit_rx)) = 'mg'
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 75 AND 85
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.dose_val_rx IS NOT NULL
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) > 0  -- Exclude zero/negative durations
),
iqr_calc AS (
  SELECT
    PERCENTILE_DISC(duration_days, 0.25) WITHIN GROUP (ORDER BY duration_days) AS q1,
    PERCENTILE_DISC(duration_days, 0.75) WITHIN GROUP (ORDER BY duration_days) AS q3
  FROM
    atorvastatin_prescriptions
)
SELECT
  q3 - q1 AS iqr_duration_days
FROM
  iqr_calc;