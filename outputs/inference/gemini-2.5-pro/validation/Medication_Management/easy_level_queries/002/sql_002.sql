WITH prescription_durations AS (
  SELECT
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
  WHERE
    -- Filter for the specific patient cohort: females aged 59-69
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    -- Filter for amiodarone prescriptions, using LOWER and LIKE for robustness
    AND LOWER(pres.drug) LIKE '%amiodarone%'
    -- Ensure start and stop times are valid for duration calculation
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime > pres.starttime
)
SELECT
  -- Calculate the IQR by subtracting the 25th percentile from the 75th
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_amiodarone_duration_days
FROM (
  -- Use APPROX_QUANTILES to find the 25th and 75th percentiles of the durations
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM
    prescription_durations
);