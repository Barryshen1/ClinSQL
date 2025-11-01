WITH
-- Step 1: Identify the cohort of ICU stays for male patients aged 68-78 at admission
cohort_stays AS (
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
    -- Calculate age at ICU admission and filter for the 68-78 range
    AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 68 AND 78
),

-- Step 2: Calculate the average respiratory rate in the first 48 hours for each stay in the cohort
avg_rr_per_stay AS (
  SELECT
    cs.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    cohort_stays AS cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    -- Filter for respiratory rate itemids from d_items
    -- 220210: Respiratory Rate, 224690: Respiratory Rate (Total), 224422: Respiratory Rate (Spontaneous)
    ce.itemid IN (220210, 224690, 224422)
    -- Filter for the first 48 hours of the ICU stay
    AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    -- Filter for plausible, non-error values
    AND ce.valuenum > 0 AND ce.valuenum < 100
  GROUP BY
    cs.stay_id
  -- Ensure the stay has at least one valid measurement to be included
  HAVING COUNT(ce.valuenum) > 0
)

-- Step 3: Calculate the percentile for a value of 12 breaths/min
SELECT
  -- Calculate the proportion of stays with an average RR <= 12 and express as a percentage
  SAFE_DIVIDE(
    COUNTIF(avg_rr <= 12),
    COUNT(stay_id)
  ) * 100 AS percentile_of_12_breaths_min
FROM
  avg_rr_per_stay;