WITH
-- Get female patients aged 37-47
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get temperature measurements (itemid 223761 = "Temperature F", 223762 = "Temperature C")
temperature_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS temperature
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  WHERE
    di.label IN ('Temperature F', 'Temperature C')
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0  -- Filter out unrealistic values
),

-- Calculate mean temperature per stay
mean_temp_per_stay AS (
  SELECT
    t.stay_id,
    AVG(t.temperature) AS mean_temperature
  FROM
    temperature_measurements t
  JOIN
    icu_stays s ON t.subject_id = s.subject_id AND t.hadm_id = s.hadm_id AND t.stay_id = s.stay_id
  GROUP BY
    t.stay_id
  HAVING
    COUNT(t.temperature) >= 1  -- Ensure at least one measurement
)

-- Compute the 75th percentile of mean temperatures
SELECT
  PERCENTILE_CONT(mean_temperature, 0.75) OVER() AS percentile_75_mean_temp
FROM
  mean_temp_per_stay
LIMIT 1;