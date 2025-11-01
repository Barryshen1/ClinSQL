WITH
-- Get male patients aged 52-62
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    eligible_patients p ON s.subject_id = p.subject_id
),

-- Get first MAP measurements for each ICU stay
first_map AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Mean Arterial Pressure'
    AND ce.charttime >= s.intime
    AND ce.charttime <= DATE_ADD(s.intime, INTERVAL 1 HOUR) -- Within first hour of admission
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id, ce.hadm_id, ce.stay_id ORDER BY ce.charttime) = 1
)

-- Calculate IQR of first MAP values
SELECT
  PERCENTILE_CONT(map_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(map_value, 0.5) OVER() AS median,
  PERCENTILE_CONT(map_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(map_value, 0.75) OVER() - PERCENTILE_CONT(map_value, 0.25) OVER() AS iqr
FROM
  first_map
LIMIT 1;