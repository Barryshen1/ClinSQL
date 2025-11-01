WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    -- Calculate age at ICU admission: anchor_age + (ICU admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT stay_id, intime
  FROM cohort
  WHERE age_admit BETWEEN 75 AND 85
),
sbp_data AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_cohort fc ON ce.stay_id = fc.stay_id
  WHERE 
    ce.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL    -- Ensure numeric values
    AND ce.charttime >= fc.intime  -- First 48 hours of ICU stay
    AND ce.charttime < DATETIME_ADD(fc.intime, INTERVAL 48 HOUR)
),
per_stay_mean_sbp AS (
  SELECT 
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM sbp_data
  GROUP BY stay_id
)
SELECT 
  -- Calculate percentile: % of stays with mean_sbp <= 140
  SAFE_DIVIDE(COUNTIF(mean_sbp <= 140), COUNT(*)) * 100 AS percentile
FROM per_stay_mean_sbp;