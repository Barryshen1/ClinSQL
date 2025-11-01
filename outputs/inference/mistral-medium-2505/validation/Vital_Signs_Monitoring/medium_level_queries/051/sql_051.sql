WITH
-- Get the itemid for heart rate from d_items
heart_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Heart Rate'
),

-- Get male patients aged 55-65
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 55 AND 65
),

-- Get ICU stays for eligible patients
icu_stays AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN eligible_patients p ON s.subject_id = p.subject_id
),

-- Get maximum heart rate for each patient during their ICU stay
max_heart_rates AS (
  SELECT
    s.subject_id,
    MAX(ce.valuenum) AS max_heart_rate
  FROM icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.hadm_id = ce.hadm_id
    AND s.stay_id = ce.stay_id
  JOIN heart_rate_item hri ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY s.subject_id
)

-- Calculate interquartile range (IQR) of max heart rates
SELECT
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] - APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS iqr
FROM max_heart_rates
LIMIT 1;