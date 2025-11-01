WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ie.stay_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
),

temp_events AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    ce.charttime,
    ce.valuenum AS temp_c
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 223762  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

temp_categorized AS (
  SELECT
    subject_id,
    stay_id,
    hadm_id,
    charttime,
    temp_c,
    CASE
      WHEN temp_c < 36.0 THEN '<36.0'
      WHEN temp_c BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN temp_c >= 38.0 THEN '>=38.0'
    END AS temp_category
  FROM temp_events
),

creatinine_48h AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    MIN(le.valuenum) AS baseline_creat_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.itemid = 50912  -- Creatinine
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN DATETIME_SUB(c.intime, INTERVAL 48 HOUR) AND c.intime
  GROUP BY c.subject_id, c.stay_id, c.hadm_id
),

creatinine_6h AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    MIN(le.valuenum) AS baseline_creat_6h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.itemid = 50912  -- Creatinine
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 6 HOUR)
  GROUP BY c.subject_id, c.stay_id, c.hadm_id
),

baseline_final AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    COALESCE(c48.baseline_creat_48h, c6.baseline_creat_6h) AS baseline_creat
  FROM cohort c
  LEFT JOIN creatinine_48h c48
    ON c.subject_id = c48.subject_id AND c.stay_id = c48.stay_id
  LEFT JOIN creatinine_6h c6
    ON c.subject_id = c6.subject_id AND c.stay_id = c6.stay_id
),

max_creatinine_7d AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    MAX(le.valuenum) AS max_creat_7d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.itemid = 50912  -- Creatinine
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.stay_id, c.hadm_id
),

aki_cohort AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    CASE
      WHEN bf.baseline_creat IS NOT NULL AND 
           ((mc.max_creat_7d >= 1.5 * bf.baseline_creat) 
            OR (mc.max_creat_7d >= bf.baseline_creat + 0.3)) THEN 1
      ELSE 0
    END AS aki
  FROM cohort c
  LEFT JOIN baseline_final bf
    ON c.subject_id = bf.subject_id AND c.stay_id = bf.stay_id
  LEFT JOIN max_creatinine_7d mc
    ON c.subject_id = mc.subject_id AND c.stay_id = mc.stay_id
)

SELECT
  tc.temp_category,
  COUNT(*) AS measurement_count,
  AVG(tc.temp_c) AS mean_temp,
  APPROX_QUANTILES(tc.temp_c, 2)[OFFSET(1)] AS median_temp,
  APPROX_QUANTILES(tc.temp_c, 4)[OFFSET(1)] AS q1_temp,
  APPROX_QUANTILES(tc.temp_c, 4)[OFFSET(3)] AS q3_temp,
  COUNT(DISTINCT tc.subject_id) AS distinct_patients,
  ROUND(SAFE_DIVIDE(SUM(aki.aki), COUNT(DISTINCT tc.subject_id)) * 100, 2) AS aki_rate_percent
FROM temp_categorized tc
LEFT JOIN aki_cohort aki
  ON tc.subject_id = aki.subject_id
GROUP BY tc.temp_category
ORDER BY tc.temp_category;