WITH filtered_prescriptions AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime
    AND SAFE_CAST(REGEXP_EXTRACT(pr.dose_val_rx, r'^(\d+)') AS FLOAT64) BETWEEN 40 AND 80
)

SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS IQR
FROM
  filtered_prescriptions;