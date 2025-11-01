WITH FirstSpO2 AS (
  -- Step 1: Find all SpO2 measurements for the target patient cohort
  -- and rank them by time to find the first one for each patient.
  SELECT
    ce.valuenum,
    -- Assign a row number to each measurement for a patient, ordered by time
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON p.subject_id = ce.subject_id
  WHERE
    -- Filter for male patients aged 62-72
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    -- Filter for SpO2 measurements using their itemid
    AND ce.itemid IN (
      220277, -- O2 saturation SpO2
      646     -- SpO2
    )
    -- Filter for valid, non-erroneous SpO2 values
    AND ce.valuenum > 0
    AND ce.valuenum <= 100
),
FirstValues AS (
  -- Step 2: Select only the first measurement (rn=1) for each patient
  SELECT
    valuenum
  FROM
    FirstSpO2
  WHERE
    rn = 1
)
-- Step 3: Calculate the Interquartile Range (IQR) on the set of first values
SELECT
  -- APPROX_QUANTILES returns an array: [min, 25th, 50th, 75th, max]
  -- IQR = 75th percentile - 25th percentile
  (APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]) AS spo2_iqr
FROM
  FirstValues;