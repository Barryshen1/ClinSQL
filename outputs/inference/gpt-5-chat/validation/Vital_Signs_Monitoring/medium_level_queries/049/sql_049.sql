WITH systolic_bp AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    ie.intime,
    ie.outtime,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND di.category = 'Blood Pressure'
    AND di.label LIKE '%Systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= ie.intime
    AND ce.charttime < ie.intime + INTERVAL 48 HOUR
),
per_stay_avg AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_sbp
  FROM systolic_bp
  GROUP BY stay_id
),
stats AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN mean_sbp < 130 THEN 1 ELSE 0 END) AS below_count,
    SUM(CASE WHEN mean_sbp = 130 THEN 1 ELSE 0 END) AS equal_count
  FROM per_stay_avg
)
SELECT
  below_count,
  total_stays,
  ROUND(100.0 * below_count / total_stays, 2) AS percentile_exclusive,
  ROUND(100.0 * (below_count + 0.5 * equal_count) / total_stays, 2) AS percentile_inclusive
FROM stats;