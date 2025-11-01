WITH
-- Step 1: Identify the cohort of ICU stays for male patients aged 39-49
CohortStays AS (
  SELECT
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Calculate age at ICU admission and filter on it
    AND ((EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age) BETWEEN 39 AND 49
),

-- Step 2: Calculate the average Mean Arterial Pressure (MAP) for each stay within the first 24 hours
StayAvgMap AS (
  SELECT
    cs.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM
    CohortStays AS cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    -- Filter for MAP itemids from d_items:
    -- 220052: Arterial Blood Pressure mean (invasive)
    -- 220181: Non Invasive Blood Pressure mean
    -- 225312: ART BP mean
    ce.itemid IN (220052, 220181, 225312)
    -- Filter for measurements within the first 24 hours of the ICU stay
    AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
    -- Ensure the value is a valid, positive number
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY
    cs.stay_id
)

-- Step 3: Calculate the percentile of 75 mmHg among the per-stay average MAPs
SELECT
  -- Count the number of stays with an average MAP at or below 75,
  -- divide by the total number of stays with valid MAP averages,
  -- and multiply by 100 to express as a percentile.
  (SUM(CASE WHEN avg_map <= 75 THEN 1 ELSE 0 END) * 100.0) / COUNT(avg_map) AS percentile_of_75_mmhg
FROM
  StayAvgMap;