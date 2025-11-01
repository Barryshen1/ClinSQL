WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
),
atorvastatin_rx AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    SAFE_CAST(pr.dose_val_rx AS FLOAT64) AS dose_val_rx,
    pr.dose_unit_rx
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
rx_durations AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.starttime,
    a.stoptime,
    TIMESTAMP_DIFF(a.stoptime, a.starttime, DAY) AS duration_days
  FROM
    atorvastatin_rx a
    INNER JOIN cohort c
      ON a.subject_id = c.subject_id
      AND a.hadm_id = c.hadm_id
  WHERE
    TIMESTAMP_DIFF(a.stoptime, a.starttime, DAY) >= 0
)
SELECT
  quantiles[OFFSET(1)] AS iqr_25th_percentile_days,
  quantiles[OFFSET(3)] AS iqr_75th_percentile_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    rx_durations
);