WITH PrescriptionDurations AS (
  SELECT
    -- Calculate the duration of each prescription in days.
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON pr.subject_id = pa.subject_id
  WHERE
    -- 1. Filter for male patients aged 36-46.
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 36 AND 46
    -- 2. Filter for inpatient digoxin prescriptions.
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.drug_type IN ('MAIN', 'BASE')
    -- 3. Ensure start and stop times are available to calculate duration.
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  -- Calculate the Interquartile Range (IQR).
  -- APPROX_QUANTILES(value, 4) returns an array: [min, q1, median, q3, max].
  -- Q3 is the 4th element (index 3), Q1 is the 2nd element (index 1).
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_duration_days
FROM
  PrescriptionDurations
WHERE
  -- 4. Exclude any prescriptions with a negative or zero duration, which could indicate data errors.
  duration_days > 0;