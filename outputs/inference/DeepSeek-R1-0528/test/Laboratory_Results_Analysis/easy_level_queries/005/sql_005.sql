WITH first_icu_stay AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    icu.outtime,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
male_first_icu_stays AS (
  SELECT 
    f.subject_id, 
    f.hadm_id, 
    f.stay_id,
    f.intime,
    f.outtime
  FROM first_icu_stay f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON f.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND f.stay_order = 1  -- First ICU stay per admission
),
first_sodium_per_admission AS (
  SELECT 
    mfis.stay_id,
    le.valuenum AS sodium_value
  FROM male_first_icu_stays mfis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mfis.hadm_id = le.hadm_id
  WHERE le.itemid = 50824  -- Serum sodium
    AND le.charttime BETWEEN mfis.intime AND mfis.outtime
    AND le.valuenum IS NOT NULL  -- Ensure numeric value
  QUALIFY ROW_NUMBER() OVER (PARTITION BY mfis.stay_id ORDER BY le.charttime) = 1  -- First sodium measurement
)
SELECT 
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] - APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS iqr
FROM first_sodium_per_admission;