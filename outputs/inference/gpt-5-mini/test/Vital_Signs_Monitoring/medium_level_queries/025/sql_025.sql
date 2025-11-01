WITH temp_items AS (
  -- identify chart itemids that look like temperature measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' OR LOWER(label) LIKE '%temperature%'
),

temps_first24 AS (
  -- temperature measurements within first 24 hours of each ICU stay,
  -- converted to Celsius when valueuom indicates Fahrenheit
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    ce.itemid,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN LOWER(IFNULL(ce.valueuom, '')) LIKE '%f%' THEN (ce.valuenum - 32) * 5.0 / 9.0
      ELSE ce.valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = i.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND ce.itemid IN (SELECT itemid FROM temp_items)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
),

per_stay_avg AS (
  -- per-stay average temperature (Celsius) during first 24 hours
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    anchor_age,
    gender,
    AVG(temp_c) AS avg_temp_c,
    COUNT(*) AS n_temps
  FROM temps_first24
  GROUP BY stay_id, subject_id, hadm_id, anchor_age, gender
)

-- empirical percentile of 37.5°C among per-stay averages for the cohort
SELECT
  SAFE_DIVIDE(COUNTIF(avg_temp_c <= 37.5), COUNT(*)) AS percentile_fraction,
  SAFE_DIVIDE(COUNTIF(avg_temp_c <= 37.5), COUNT(*)) * 100.0 AS percentile_percent,
  COUNT(*) AS n_stays_in_cohort
FROM per_stay_avg;