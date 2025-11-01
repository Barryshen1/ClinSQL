WITH ValidPrescriptions AS (
  SELECT
    -- Calculate the duration of each prescription in days.
    TIMESTAMP_DIFF(presc.stoptime, presc.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    ON pat.subject_id = presc.subject_id
  WHERE
    -- 1. Filter for female patients aged 75-85
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
    -- 2. Filter for Atorvastatin prescriptions
    AND LOWER(presc.drug) LIKE '%atorvastatin%'
    -- 3. Filter for high-intensity single dose (40-80 mg)
    AND presc.dose_unit_rx = 'mg'
    AND SAFE_CAST(presc.dose_val_rx AS NUMERIC) BETWEEN 40 AND 80
    -- 4. Ensure the prescription has a valid start and stop time for duration calculation
    AND presc.starttime IS NOT NULL
    AND presc.stoptime IS NOT NULL
    AND presc.stoptime > presc.starttime
)
SELECT
  -- Calculate the 25th and 75th percentiles (Q1 and Q3)
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q1_duration_days,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q3_duration_days,
  -- Calculate the Interquartile Range (IQR)
  (APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)]) AS iqr_duration_days
FROM
  ValidPrescriptions
WHERE
  -- Further ensure we only consider positive durations
  duration_days > 0;