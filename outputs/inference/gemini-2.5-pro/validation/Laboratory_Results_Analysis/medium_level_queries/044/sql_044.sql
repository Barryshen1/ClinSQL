WITH
  -- Step 1: Identify the first Troponin T measurement for each hospital admission
  initial_troponin_per_admission AS (
    SELECT
      hadm_id,
      valuenum AS initial_troponin_t
    FROM
      (
        SELECT
          hadm_id,
          charttime,
          valuenum,
          -- Assign a rank to each measurement within an admission, ordered by time
          ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
        FROM
          `physionet-data.mimiciv_3_1_hosp.labevents`
        WHERE
          itemid = 51003  -- Troponin T
          AND valuenum IS NOT NULL -- Ensure the value is numeric
      ) AS ranked_troponins
    WHERE
      rn = 1  -- Select only the first measurement
  ),

  -- Step 2: Join with patient demographics and apply all filters
  filtered_cohort AS (
    SELECT
      it.initial_troponin_t
    FROM
      initial_troponin_per_admission AS it
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON it.hadm_id = adm.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    WHERE
      -- Filter for male patients
      p.gender = 'M'
      -- Filter for age at admission between 54 and 64
      AND (
        p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year
      ) BETWEEN 54 AND 64
      -- Filter for initial Troponin T > 0.01 ng/mL
      AND it.initial_troponin_t > 0.01
  )

-- Step 3: Calculate and report the final summary statistics
SELECT
  COUNT(initial_troponin_t) AS n,
  AVG(initial_troponin_t) AS mean,
  STDDEV(initial_troponin_t) AS std_dev,
  MIN(initial_troponin_t) AS min,
  MAX(initial_troponin_t) AS max,
  -- Use APPROX_QUANTILES to find percentiles and select the specific values
  APPROX_QUANTILES(initial_troponin_t, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(initial_troponin_t, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(initial_troponin_t, 100)[OFFSET(75)] AS p75
FROM
  filtered_cohort;