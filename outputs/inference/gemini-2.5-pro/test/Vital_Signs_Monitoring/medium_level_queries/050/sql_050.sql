WITH
  -- Step 1: Identify ICU stays for female patients aged 67-77 at the time of admission
  cohort_stays AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      -- Refined age calculation for accuracy at the time of ICU admission
      AND DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age BETWEEN 67 AND 77
  ),
  -- Step 2 & 3: Calculate the average heart rate per stay during the first 24 hours
  avg_hr_per_stay AS (
    SELECT
      cs.stay_id,
      AVG(ce.valuenum) AS avg_hr
    FROM cohort_stays AS cs
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON cs.stay_id = ce.stay_id
    WHERE
      -- Filter for Heart Rate itemids (Metavision and CareVue)
      ce.itemid IN (220045, 211)
      -- Filter for the first 24 hours of the ICU stay
      AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
      -- Filter for valid, numeric heart rate values
      AND ce.valuenum > 0 AND ce.valuenum < 300
    GROUP BY
      cs.stay_id
    -- Ensure we only include stays that had at least one HR measurement
    HAVING
      COUNT(ce.valuenum) > 0
  )
-- Step 4: Calculate the percentile of a 110 bpm average HR among the cohort
SELECT
  100.0 * SUM(
    CASE
      WHEN avg_hr <= 110
      THEN 1
      ELSE 0
    END
  ) / COUNT(stay_id) AS percentile_of_110_bpm
FROM avg_hr_per_stay;