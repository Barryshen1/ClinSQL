WITH cohort_hr AS (
  SELECT 
    icu.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON icu.stay_id = ce.stay_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND ce.itemid = 220045  -- Heart rate itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.charttime < icu.outtime
),
per_stay_median AS (
  SELECT 
    stay_id,
    APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_hr  -- Median per stay
  FROM cohort_hr
  GROUP BY stay_id
),
quartiles AS (
  SELECT APPROX_QUANTILES(median_hr, 4) AS q_arr  -- Array: [min, Q1, median, Q3, max]
  FROM per_stay_median
)
SELECT 
  q_arr[SAFE_OFFSET(3)] - q_arr[SAFE_OFFSET(1)] AS iqr  -- IQR = Q3 - Q1
FROM quartiles;