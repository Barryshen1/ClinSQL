WITH FirstSpO2PerAdmission AS (
  -- Step 3: Rank SpO2 measurements by time for each admission to find the first one
  SELECT
    ce.valuenum,
    -- Assign a row number to each measurement within a patient's hospital admission, ordered by time.
    ROW_NUMBER() OVER(PARTITION BY p.subject_id, ce.hadm_id ORDER BY ce.charttime ASC) as rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  -- Step 2: Join with chartevents to get SpO2 measurements
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON p.subject_id = ce.subject_id
  WHERE
    -- Step 1: Filter for the specified patient cohort
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- Filter for SpO2 itemid
    AND ce.itemid = 220277 -- 'O2 saturation pulseoxymetry'
    -- Filter for valid, plausible SpO2 values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 1 AND 100
)
-- Step 4: Calculate the standard deviation of the first SpO2 values
SELECT
  STDDEV(valuenum) AS stddev_first_spo2
FROM
  FirstSpO2PerAdmission
WHERE
  -- Only consider the first measurement for each admission (rn=1)
  rn = 1;