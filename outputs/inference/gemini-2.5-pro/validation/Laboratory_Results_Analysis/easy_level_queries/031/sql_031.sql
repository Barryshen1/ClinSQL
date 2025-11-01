WITH male_icu_admissions AS (
  -- First, identify all hospital admissions (hadm_id) for male patients
  -- that included at least one ICU stay.
  SELECT DISTINCT icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
)
SELECT
  -- Calculate the 75th percentile of the collected potassium values.
  -- APPROX_QUANTILES is an efficient function for this purpose in BigQuery.
  APPROX_QUANTILES(le.valuenum, 100)[OFFSET(75)] AS potassium_p75
FROM male_icu_admissions mia
-- Join with admissions to get the hospital discharge time for each relevant admission.
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON mia.hadm_id = adm.hadm_id
-- Join with labevents to get potassium measurements for those admissions.
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON mia.hadm_id = le.hadm_id
WHERE
  -- Filter for serum potassium itemids. 50971 is 'Potassium', 50822 is 'Potassium, Whole Blood'.
  le.itemid IN (50971, 50822)
  -- Filter for measurements taken on the same calendar day as hospital discharge.
  AND DATE(le.charttime) = DATE(adm.dischtime)
  -- Ensure the value is a number.
  AND le.valuenum IS NOT NULL
  -- Add a plausible physiological range for potassium (mEq/L) to exclude clear errors.
  AND le.valuenum > 2 AND le.valuenum < 10;