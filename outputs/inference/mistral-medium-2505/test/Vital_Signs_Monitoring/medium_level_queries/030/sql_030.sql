WITH
-- Get female patients aged 81-91
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get temperature measurements in first 24h of ICU stay
temp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS temperature_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  WHERE
    ce.itemid IN (223761, 223762) -- Temperature F and C
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate mean temperature per stay (first 24h)
stay_temp_stats AS (
  SELECT
    stay_id,
    AVG(temperature_celsius) AS mean_temp,
    COUNT(*) AS temp_measurements_count
  FROM
    temp_measurements
  GROUP BY
    stay_id
),

-- Classify stays into temperature groups
temp_groups AS (
  SELECT
    s.stay_id,
    s.mean_temp,
    CASE
      WHEN s.mean_temp < 36.0 THEN '<36.0'
      WHEN s.mean_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN s.mean_temp >= 38.0 THEN '>=38.0'
      ELSE NULL
    END AS temp_group,
    s.temp_measurements_count
  FROM
    stay_temp_stats s
  WHERE
    s.mean_temp IS NOT NULL
),

-- Calculate percentiles for the entire dataset
temp_percentiles AS (
  SELECT
    PERCENTILE_CONT(mean_temp, 0.25) OVER() AS q1_temp,
    PERCENTILE_CONT(mean_temp, 0.5) OVER() AS median_temp,
    PERCENTILE_CONT(mean_temp, 0.75) OVER() AS q3_temp
  FROM
    temp_groups
  LIMIT 1
),

-- Count stays with no temperature measurements in first 24h
missing_temp_stays AS (
  SELECT
    COUNT(DISTINCT s.stay_id) AS missing_count
  FROM
    icu_stays s
  LEFT JOIN
    stay_temp_stats t ON s.stay_id = t.stay_id
  WHERE
    t.stay_id IS NULL
),

-- Total stays for MI rate calculation
total_stays AS (
  SELECT
    COUNT(DISTINCT stay_id) AS total_count
  FROM
    icu_stays
)

-- Final aggregation
SELECT
  t.temp_group,
  COUNT(DISTINCT t.stay_id) AS N,
  ROUND(AVG(t.mean_temp), 2) AS mean_temp,
  ROUND(p.median_temp, 2) AS median_temp,
  ROUND(p.q1_temp, 2) AS q1_temp,
  ROUND(p.q3_temp, 2) AS q3_temp,
  ROUND((p.q3_temp - p.q1_temp), 2) AS IQR,
  ROUND((SELECT missing_count FROM missing_temp_stays) * 100.0 / (SELECT total_count FROM total_stays), 2) AS MI_rate_percentage
FROM
  temp_groups t
CROSS JOIN
  temp_percentiles p
GROUP BY
  t.temp_group, p.median_temp, p.q1_temp, p.q3_temp
ORDER BY
  t.temp_group;