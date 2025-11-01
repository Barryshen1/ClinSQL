WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%'
),

-- Step 2: Get male ICU patients aged 73-83 and their ICU stays
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
),

-- Step 3: Calculate mean SpO2 per ICU stay in first 24h
mean_spo2_per_stay AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 100 -- plausible SpO2 values
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),

-- Step 4: Compute percentile for mean SpO2 = 92
percentile AS (
  SELECT
    COUNTIF(mean_spo2 <= 92) AS num_below_or_equal,
    COUNT(*) AS total_stays
  FROM mean_spo2_per_stay
)

SELECT
  num_below_or_equal,
  total_stays,
  ROUND(100.0 * num_below_or_equal / total_stays, 2) AS percentile_for_92
FROM percentile;