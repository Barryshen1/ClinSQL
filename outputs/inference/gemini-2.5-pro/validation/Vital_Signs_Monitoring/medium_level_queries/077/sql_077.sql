WITH
-- Step 1: Identify the cohort of ICU stays for female patients aged 42-52.
cohort_stays AS (
  SELECT
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
    -- Calculate patient's age at the time of hospital admission.
    AND (
      pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 42 AND 52
),

-- Step 2: Calculate the average heart rate for each ICU stay in the cohort.
avg_hr_per_stay AS (
  SELECT
    cs.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM cohort_stays AS cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      220045, -- Heart Rate (Metavision)
      211 -- Heart Rate (CareVue)
    )
    -- Filter for valid, physiological values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY
    cs.stay_id
)

-- Step 3: Calculate the final cohort size and the percentile of 90 bpm.
SELECT
  COUNT(stay_id) AS cohort_size,
  -- The percentile of a value is the percentage of observations falling at or below it.
  100.0 * COUNTIF(avg_hr <= 90) / COUNT(stay_id) AS percentile_of_90_bpm
FROM avg_hr_per_stay;