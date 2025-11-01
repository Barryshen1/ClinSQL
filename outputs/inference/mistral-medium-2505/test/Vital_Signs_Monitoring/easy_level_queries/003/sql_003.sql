WITH
-- Get male patients aged 40-50
male_patients_40_50 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients_40_50 p
  ON
    s.subject_id = p.subject_id
),

-- Get heart rate measurements for these stays
heart_rates AS (
  SELECT
    i.stay_id,
    c.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
  ON
    c.subject_id = i.subject_id
    AND c.hadm_id = i.hadm_id
  WHERE
    c.itemid = 220045  -- Heart Rate
    AND c.valuenum IS NOT NULL
),

-- Calculate mean heart rate per stay
stay_mean_heart_rates AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS mean_heart_rate
  FROM
    heart_rates
  GROUP BY
    stay_id
)

-- Calculate median of per-stay mean heart rates
SELECT
  PERCENTILE_CONT(mean_heart_rate, 0.5) OVER() AS median_mean_heart_rate
FROM
  stay_mean_heart_rates
LIMIT 1;