WITH heart_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
),

-- Step 2: Get qualifying ICU stays (male, age 40-50)
qualified_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
),

-- Step 3: Compute per-stay mean heart rate
per_stay_mean_hr AS (
  SELECT
    qs.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM qualified_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON qs.subject_id = ce.subject_id
    AND qs.hadm_id = ce.hadm_id
    AND qs.stay_id = ce.stay_id
  INNER JOIN heart_rate_items hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY qs.stay_id
)

-- Step 4: Compute median of per-stay means
SELECT
  APPROX_QUANTILES(mean_hr, 2)[OFFSET(1)] AS median_per_stay_mean_heart_rate
FROM per_stay_mean_hr;