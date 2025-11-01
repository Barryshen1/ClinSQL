WITH filtered_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.starttime,
    pr.stoptime,
    -- Calculate age at prescription time
    pt.anchor_age + (EXTRACT(YEAR FROM pr.starttime) - pt.anchor_year) AS age_at_prescription,
    -- Compute duration in fractional days
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pr.subject_id = pt.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'  -- Case-insensitive match
    AND pr.dose_val_rx IN ('40', '80')     -- High-intensity doses
    AND pr.dose_unit_rx = 'mg'             -- Ensure unit is milligrams
    AND pt.gender = 'F'                    -- Female patients
    AND pr.stoptime IS NOT NULL            -- Exclude NULL end times
    AND pr.stoptime > pr.starttime         -- Ensure valid duration
),
duration_quantiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS arr  -- Get quartiles [Q0, Q1, Q2, Q3, Q4]
  FROM
    filtered_prescriptions
  WHERE
    age_at_prescription BETWEEN 75 AND 85  -- Age filter applied here
)
SELECT
  arr[OFFSET(1)] AS q1,                     -- 25th percentile (Q1)
  arr[OFFSET(3)] AS q3,                     -- 75th percentile (Q3)
  arr[OFFSET(3)] - arr[OFFSET(1)] AS iqr    -- IQR = Q3 - Q1
FROM
  duration_quantiles;