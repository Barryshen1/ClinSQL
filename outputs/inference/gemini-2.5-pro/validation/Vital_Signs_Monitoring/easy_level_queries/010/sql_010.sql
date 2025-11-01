WITH cohort_stays AS (
  -- Step 1: Identify all ICU stay_ids for female patients aged 71-81
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    ON p.subject_id = ad.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ad.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) + p.anchor_age BETWEEN 71 AND 81
),

max_dbp_per_stay AS (
  -- Step 2: For each stay in the cohort, find the maximum diastolic blood pressure
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    cohort_stays
    ON ce.stay_id = cohort_stays.stay_id
  WHERE
    ce.itemid IN (
      220051, -- Arterial Blood Pressure diastolic
      220180, -- Non Invasive Blood Pressure diastolic
      225310, -- NBP-Diastolic
      8368,   -- Arterial BP [Diastolic] (from MetaVision)
      8441,   -- NBP [Diastolic] (from MetaVision)
      8555    -- NBP [Diastolic] (from MetaVision)
    )
    -- Add a plausible physiological range to filter out erroneous values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY
    ce.stay_id
)

-- Step 3: Calculate the median of the per-stay maximums
SELECT
  APPROX_QUANTILES(max_dbp, 2)[OFFSET(1)] AS median_of_per_stay_maximum_dbp
FROM
  max_dbp_per_stay;