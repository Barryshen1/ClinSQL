WITH cohort_stays AS (
  -- First, define the patient cohort based on demographics and ICU admission
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
    AND p.anchor_age BETWEEN 66 AND 76
),
ventilated_stays AS (
  -- Second, identify all ICU stays that involved mechanical ventilation
  SELECT DISTINCT
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    itemid = 225794 -- Mechanical Ventilation
)
-- Finally, calculate the IQR of SBP for the filtered cohort in the first 6 hours
SELECT
  -- Use APPROX_QUANTILES to find the 75th and 25th percentiles and calculate the difference (IQR)
  -- We ask for 101 quantiles to get percentiles 0-100, then use OFFSET for 0-based index access.
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(25)] AS sbp_interquartile_range
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
-- Ensure the measurement belongs to a patient in our cohort
INNER JOIN
  cohort_stays AS cs
  ON ce.stay_id = cs.stay_id
-- Ensure the patient was mechanically ventilated during this stay
INNER JOIN
  ventilated_stays AS vs
  ON ce.stay_id = vs.stay_id
WHERE
  -- Filter for SBP itemids (both invasive and non-invasive)
  ce.itemid IN (
    220050, -- Arterial Blood Pressure systolic
    220179  -- Non Invasive Blood Pressure systolic
  )
  -- Filter for measurements taken within the first 6 hours of the ICU stay
  AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 6 HOUR)
  -- Clean the data by removing null and invalid values
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0 AND ce.valuenum < 300;