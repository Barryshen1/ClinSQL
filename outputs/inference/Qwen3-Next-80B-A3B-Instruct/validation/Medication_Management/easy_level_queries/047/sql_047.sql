WITH atorvastatin_prescriptions AS (
  SELECT
    p.subject_id,
    p.stoptime,
    p.starttime,
    SAFE_CAST(p.dose_val_rx AS FLOAT64) AS dose_val_rx_numeric
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime >= p.starttime
),
duration_days AS (
  SELECT
    DATETIME_DIFF(stoptime, starttime, DAY) AS prescription_duration_days
  FROM
    atorvastatin_prescriptions
)
SELECT
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(1)] AS iqr_days
FROM
  duration_days;