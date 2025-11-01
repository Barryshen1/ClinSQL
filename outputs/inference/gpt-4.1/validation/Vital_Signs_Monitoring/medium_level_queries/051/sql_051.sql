WITH heart_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
  LIMIT 1
),

-- Step 2: Get male patients aged 55-65
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 55 AND 65
),

-- Step 3: Get all ICU stays for eligible patients
eligible_icustays AS (
  SELECT icu.subject_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN eligible_patients p
    ON icu.subject_id = p.subject_id
),

-- Step 4: Get heart rate measurements during ICU stays
heart_rate_measurements AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum
  FROM eligible_icustays icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
  INNER JOIN heart_rate_itemid hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
),

-- Step 5: For each patient, get their maximum heart rate during any ICU stay
max_hr_per_patient AS (
  SELECT
    subject_id,
    MAX(valuenum) AS max_heart_rate
  FROM heart_rate_measurements
  GROUP BY subject_id
)

-- Step 6: Compute the IQR of these maxima
SELECT
  APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(1)] AS q1_25th_percentile,
  APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(3)] AS q3_75th_percentile,
  APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(3)] - APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(1)] AS interquartile_range
FROM max_hr_per_patient;