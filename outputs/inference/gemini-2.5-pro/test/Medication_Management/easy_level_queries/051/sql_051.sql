WITH DigoxinDurations AS (
  SELECT
    -- Calculate the duration of each prescription in days.
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON pat.subject_id = pres.subject_id
  WHERE
    -- 1. Filter for the patient cohort: males aged 86-96.
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 86 AND 96
    -- 2. Filter for digoxin prescriptions. LOWER and LIKE make the search robust.
    AND LOWER(pres.drug) LIKE '%digoxin%'
    -- 3. Ensure the duration can be calculated and is a positive value.
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime
)
-- 4. Calculate the 25th, 75th percentiles, and the Interquartile Range (IQR).
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_days,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS percentile_75_days,
  (
    APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)]
  ) AS iqr_days
FROM
  DigoxinDurations;