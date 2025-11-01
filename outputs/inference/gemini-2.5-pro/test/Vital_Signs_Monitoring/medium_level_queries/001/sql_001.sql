WITH
  -- Step 1: Identify the cohort of female patients aged 45-55 at admission.
  patient_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 45 AND 55
  ),
  -- Step 2 & 3: Get SBP measurements for this cohort in the first 24 hours of their ICU stay.
  first_24hr_sbp AS (
    SELECT
      icu.subject_id,
      icu.stay_id,
      ce.valuenum
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      patient_cohort AS cohort
      ON icu.subject_id = cohort.subject_id AND icu.hadm_id = cohort.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON icu.stay_id = ce.stay_id
    WHERE
      -- Filter for SBP measurements within the first 24 hours of the ICU stay
      ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
      -- ITEMIDs for Systolic Blood Pressure (arterial, non-invasive, and ART)
      AND ce.itemid IN (220050, 220179, 225309)
      -- Ensure the value is a plausible number for averaging
      AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
  ),
  -- Step 4: Calculate the average SBP per ICU stay.
  avg_sbp_per_stay AS (
    SELECT
      subject_id,
      stay_id,
      AVG(valuenum) AS avg_sbp
    FROM
      first_24hr_sbp
    GROUP BY
      subject_id,
      stay_id
  ),
  -- Step 5: Categorize each stay's average SBP.
  categorized_stays AS (
    SELECT
      subject_id,
      CASE
        WHEN avg_sbp < 140
        THEN '<140 mmHg'
        WHEN avg_sbp BETWEEN 140 AND 159
        THEN '140-159 mmHg'
        WHEN avg_sbp >= 160
        THEN '>=160 mmHg'
        ELSE NULL
      END AS sbp_category
    FROM
      avg_sbp_per_stay
  )
-- Step 6: Count the number of unique patients in each category.
SELECT
  sbp_category,
  COUNT(DISTINCT subject_id) AS number_of_patients
FROM
  categorized_stays
WHERE
  sbp_category IS NOT NULL
GROUP BY
  sbp_category
ORDER BY
  -- Custom order to ensure logical sorting of categories
  CASE
    WHEN sbp_category = '<140 mmHg' THEN 1
    WHEN sbp_category = '140-159 mmHg' THEN 2
    WHEN sbp_category = '>=160 mmHg' THEN 3
  END;