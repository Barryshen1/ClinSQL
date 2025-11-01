WITH icu_stays_with_age AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
filtered_stays AS (
  SELECT stay_id, intime
  FROM icu_stays_with_age
  WHERE gender = 'F'
    AND age >= 38
    AND age <= 48
),
bp_measurements AS (
  SELECT 
    fs.stay_id,
    ce.valuenum AS sbp
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
    AND ce.charttime >= fs.intime
    AND ce.charttime < TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
stay_avg AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM bp_measurements
  GROUP BY stay_id
)
SELECT 
  (COUNT(CASE WHEN avg_sbp <= 130 THEN 1 END) * 100.0) / COUNT(*) AS percentile_rank
FROM stay_avg;