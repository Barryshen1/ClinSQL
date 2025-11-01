WITH
-- Get male patients aged 74-84
target_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 74 AND 84
),

-- Get temperature itemids (assuming "Temperature F" is the label)
temp_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label = 'Temperature F'
),

-- Get all temperature measurements for target patients
temp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS temp_f
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    target_patients tp ON ce.subject_id = tp.subject_id
  JOIN
    temp_itemids ti ON ce.itemid = ti.itemid
  WHERE
    ce.valuenum IS NOT NULL
),

-- Calculate minimum temperature per stay
min_temp_per_stay AS (
  SELECT
    stay_id,
    MIN(temp_f) AS min_temp_f
  FROM
    temp_measurements
  GROUP BY
    stay_id
)

-- Calculate median of minimum temperatures across all stays
SELECT
  PERCENTILE_CONT(min_temp_f, 0.5) OVER() AS median_min_temp_f
FROM
  min_temp_per_stay
LIMIT 1;