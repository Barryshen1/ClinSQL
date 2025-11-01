WITH temperature_itemids AS (
  -- Find itemids for temperature in Celsius
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' AND (
    LOWER(unitname) LIKE '%c%' OR LOWER(label) LIKE '%celsius%'
  )
),
male_icu_patients AS (
  -- Get male ICU stays for patients aged 82-92
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
),
first24hr_temps AS (
  -- Get temperature measurements in first 24h of ICU stay
  SELECT
    temp.stay_id,
    temp.charttime,
    temp.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` temp
  JOIN male_icu_patients icu
    ON temp.stay_id = icu.stay_id
  WHERE temp.itemid IN (SELECT itemid FROM temperature_itemids)
    AND temp.valuenum IS NOT NULL
    AND temp.charttime >= icu.intime
    AND temp.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    -- Optionally, filter by valueuom if needed:
    -- AND (LOWER(temp.valueuom) LIKE '%c%' OR temp.valueuom IS NULL)
),
avg_temp_per_stay AS (
  -- Compute average temperature per stay
  SELECT
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM first24hr_temps
  GROUP BY stay_id
),
percentile_calc AS (
  -- Calculate percentile for 37.5°C
  SELECT
    COUNTIF(avg_temp <= 37.5) AS num_leq_375,
    COUNT(*) AS total_stays
  FROM avg_temp_per_stay
)
SELECT
  SAFE_DIVIDE(num_leq_375, total_stays) * 100 AS percentile_37_5_c
FROM percentile_calc;