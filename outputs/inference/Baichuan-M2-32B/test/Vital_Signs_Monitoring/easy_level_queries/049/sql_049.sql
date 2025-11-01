WITH cohort AS (
  SELECT 
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),
bp_data AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS bp_value,
    d.itemid,
    d.label,
    d.unitname
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  INNER JOIN cohort
    ON c.subject_id = cohort.subject_id
    AND c.hadm_id = cohort.hadm_id
    AND c.stay_id = cohort.stay_id
  WHERE c.valuenum IS NOT NULL
    AND d.category = 'Vital Signs'
    AND d.unitname = 'mmHg'
    AND d.itemid IN (442, 443, 456, 457)  -- systolic: 442,456; diastolic:443,457
    AND c.charttime BETWEEN cohort.intime AND cohort.intime + INTERVAL 24 HOUR
    AND c.valuenum BETWEEN 40 AND 300  -- reasonable BP range
),
systolic AS (
  SELECT * FROM bp_data WHERE itemid IN (442, 456)
),
diastolic AS (
  SELECT * FROM bp_data WHERE itemid IN (443, 457)
),
matched_bp AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.charttime AS systolic_time,
    s.bp_value AS systolic,
    d.charttime AS diastolic_time,
    d.bp_value AS diastolic,
    ABS(TIMESTAMP_DIFF(s.charttime, d.charttime, MINUTE)) AS time_diff
  FROM systolic s
  LEFT JOIN diastolic d
    ON s.subject_id = d.subject_id
    AND s.hadm_id = d.hadm_id
    AND s.stay_id = d.stay_id
    AND ABS(TIMESTAMP_DIFF(s.charttime, d.charttime, MINUTE)) <= 5
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id, s.stay_id, s.charttime ORDER BY time_diff) = 1
),
map_values AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    systolic_time AS charttime,
    (systolic + 2 * diastolic) / 3 AS map
  FROM matched_bp
  WHERE diastolic IS NOT NULL
),
first24h_map AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(map) AS mean_map_24h
  FROM map_values
  GROUP BY subject_id, hadm_id, stay_id
)
SELECT STDDEV(mean_map_24h) AS std_dev
FROM first24h_map;