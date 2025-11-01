WITH cohort_stays AS (
  -- Step 1: Identify all ICU stays for female patients aged 38-48
  SELECT
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    -- Calculate age at the time of ICU admission
    AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 38 AND 48
),

sbp_measurements AS (
  -- Step 2: Extract all SBP measurements for the cohort within the first 48 hours
  SELECT
    cs.stay_id,
    ce.valuenum
  FROM
    cohort_stays AS cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    -- Filter for SBP itemids (both invasive and non-invasive)
    ce.itemid IN (
      51,      -- Arterial BP [Systolic]
      442,     -- Manual BP [Systolic]
      455,     -- NBP [Systolic]
      6701,    -- Arterial BP #2 [Systolic]
      220050,  -- Arterial Blood Pressure systolic
      220179,  -- Non Invasive Blood Pressure systolic
      225309   -- ART BP Systolic
    )
    -- Filter for the first 48 hours of the ICU stay
    AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    -- Filter for plausible SBP values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
),

stay_avg_sbp AS (
  -- Step 3: Calculate the average SBP for each ICU stay
  SELECT
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM
    sbp_measurements
  GROUP BY
    stay_id
)

-- Step 4: Calculate what percentile an average SBP of 130 mmHg falls into
SELECT
  -- This calculates the percentage of stays with an average SBP at or below 130
  (
    COUNTIF(avg_sbp <= 130) / COUNT(stay_id)
  ) * 100 AS percentile_of_130_mmhg_sbp
FROM
  stay_avg_sbp;