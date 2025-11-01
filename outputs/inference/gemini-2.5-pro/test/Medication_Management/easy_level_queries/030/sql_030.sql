WITH AmiodaroneDurations AS (
  -- Step 1 & 2: Select amiodarone prescriptions for the target patient cohort
  SELECT
    rx.subject_id,
    rx.hadm_id,
    -- Step 3: Calculate the duration of each prescription in hours
    DATETIME_DIFF(rx.stoptime, rx.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON rx.subject_id = pat.subject_id
  WHERE
    -- Filter for female patients aged 42-52
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 42 AND 52
    -- Filter for amiodarone prescriptions
    AND LOWER(rx.drug) LIKE '%amiodarone%'
    -- Ensure the start and stop times are valid for duration calculation
    AND rx.starttime IS NOT NULL
    AND rx.stoptime IS NOT NULL
    AND rx.stoptime > rx.starttime
)
-- Step 4: Calculate the 25th percentile of the durations
SELECT
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS percentile_25_amiodarone_duration_hours
FROM
  AmiodaroneDurations;