WITH atorvastatin_rx AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    -- Duration in days
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND pr.drug IS NOT NULL
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_unit_rx IS NOT NULL
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
)
SELECT
  quantiles[OFFSET(1)] AS q1_days,
  quantiles[OFFSET(3)] AS q3_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    atorvastatin_rx
);