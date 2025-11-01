WITH high_intensity_rx AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pr.starttime,
    pr.stoptime,
    CAST(pr.dose_val_rx AS FLOAT64) AS dose_mg,
    pr.dose_unit_rx,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  ON
    p.subject_id = pr.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) IN (40, 80)
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
)
SELECT
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr_days,
  quartiles[OFFSET(1)] AS q1_days,
  quartiles[OFFSET(2)] AS median_days,
  quartiles[OFFSET(3)] AS q3_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quartiles
  FROM
    high_intensity_rx
);