WITH
-- Get female patients aged 67-77
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
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

-- Get heart rate measurements in the first 24 hours of each ICU stay
heart_rate_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE
    d.label = 'Heart Rate'
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.valuenum > 0  -- Exclude invalid values
),

-- Calculate average HR per ICU stay
avg_hr_per_stay AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS avg_heart_rate
  FROM
    heart_rate_measurements
  GROUP BY
    stay_id
  HAVING
    COUNT(heart_rate) > 0  -- Ensure at least one HR measurement
),

-- Calculate percentiles for all average HR values
percentiles AS (
  SELECT
    avg_heart_rate,
    PERCENT_RANK() OVER (ORDER BY avg_heart_rate) AS percentile
  FROM
    avg_hr_per_stay
)

-- Find the percentile for an average HR of 110 bpm
SELECT
  MAX(percentile) AS percentile_for_110
FROM
  percentiles
WHERE
  avg_heart_rate <= 110;