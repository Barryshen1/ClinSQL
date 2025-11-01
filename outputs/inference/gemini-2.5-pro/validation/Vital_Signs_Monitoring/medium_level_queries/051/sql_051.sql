WITH icu_cohort AS (
  -- Step 1: Identify ICU stays for male patients aged 55-65
  SELECT
    i.subject_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
patient_max_hr AS (
  -- Step 2: Find the maximum heart rate for each patient in the cohort
  SELECT
    ce.subject_id,
    MAX(ce.valuenum) AS max_heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    icu_cohort
    ON ce.stay_id = icu_cohort.stay_id
  WHERE
    ce.itemid = 220045 -- Heart Rate
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.subject_id
)
-- Step 3: Calculate the interquartile range (IQR) of the maximum heart rates
SELECT
  -- The APPROX_QUANTILES function with 4 buckets returns [min, 25th, 50th, 75th, max]
  -- We subtract the 25th percentile (index 1) from the 75th percentile (index 3)
  APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(3)] - APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(1)] AS iqr_of_max_heart_rate
FROM
  patient_max_hr;