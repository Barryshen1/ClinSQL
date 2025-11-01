WITH
-- Get male patients aged 82-92
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 82 AND 92
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
    male_patients p ON s.subject_id = p.subject_id
),

-- Get temperature measurements in Celsius during first 24 hours of ICU stay
temp_celsius AS (
  SELECT
    c.stay_id,
    c.charttime,
    CASE
      WHEN c.itemid = 223762 THEN c.valuenum  -- Already in Celsius
      WHEN c.itemid = 223761 THEN (c.valuenum - 32) * 5/9  -- Convert F to C
    END AS temperature_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.stay_id = s.stay_id
  WHERE
    c.itemid IN (223762, 223761)
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND (
      (c.itemid = 223762 AND c.valuenum BETWEEN 30 AND 45) OR
      (c.itemid = 223761 AND c.valuenum BETWEEN 86 AND 113)
    )
),

-- Compute average temperature per stay
avg_temp_per_stay AS (
  SELECT
    stay_id,
    AVG(temperature_celsius) AS avg_temp_celsius
  FROM
    temp_celsius
  GROUP BY
    stay_id
  HAVING
    COUNT(temperature_celsius) >= 1  -- Ensure at least one measurement
),

-- Calculate percentile rank for each average temperature
temp_with_percentile AS (
  SELECT
    avg_temp_celsius,
    PERCENT_RANK() OVER (ORDER BY avg_temp_celsius) AS percentile_rank
  FROM
    avg_temp_per_stay
)

-- Find the percentile rank for 37.5°C (or closest value)
SELECT
  percentile_rank
FROM
  temp_with_percentile
WHERE
  avg_temp_celsius = (
    SELECT
      MAX(avg_temp_celsius)
    FROM
      temp_with_percentile
    WHERE
      avg_temp_celsius <= 37.5
  )
LIMIT 1;