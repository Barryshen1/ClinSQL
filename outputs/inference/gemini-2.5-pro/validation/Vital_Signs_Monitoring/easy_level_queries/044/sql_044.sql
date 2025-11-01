WITH
  -- Step 1: Define the patient cohort of female patients aged 82-92.
  patient_cohort AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'F'
      AND anchor_age BETWEEN 82 AND 92
  ),

  -- Step 2: For each hospital stay in the cohort, find the maximum MAP recorded.
  max_map_per_hadm AS (
    SELECT
      ce.hadm_id,
      MAX(ce.valuenum) AS max_map
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      patient_cohort AS pc
      ON ce.subject_id = pc.subject_id
    WHERE
      -- ITEMIDs for Mean Arterial Pressure (both invasive and non-invasive)
      ce.itemid IN (220052, 220181, 225312)
      -- Apply a reasonable range to filter out clear data entry errors
      AND ce.valuenum > 0 AND ce.valuenum < 300
    GROUP BY
      ce.hadm_id
  )

-- Step 3: Calculate the median of the collected maximum MAP values.
SELECT DISTINCT
  PERCENTILE_CONT(max_map, 0.5) OVER () AS median_of_max_map
FROM
  max_map_per_hadm;