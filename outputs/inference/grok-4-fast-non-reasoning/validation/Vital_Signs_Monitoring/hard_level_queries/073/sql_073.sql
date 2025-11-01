WITH cohort AS (
  -- Base cohort: female, age 47-57, ICH principal diagnosis, ICU stay
  SELECT DISTINCT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON i.hadm_id = d.hadm_id AND d.seq_num = 1 AND d.icd_version = '10' AND d.icd_code LIKE 'I61%'
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 47 AND 57
),

vital_itemids AS (
  -- Specific itemids for key vitals (HR, RR, Temp, Sys/Dia BP)
  SELECT itemid FROM UNNEST([
    211, 220045,  -- Heart Rate
    618, 220210,  -- Respiratory Rate
    676, 678, 679, 223762,  -- Temperature
    51, 442, 455, 6701, 220179, 220050,  -- Systolic BP
    8368, 8440, 8441, 8555, 220180, 220051  -- Diastolic BP
  ]) AS itemid
),

vitals AS (
  -- Extract vital signs in first 72h
  SELECT 
    c.stay_id,
    c.intime,
    ce.charttime,
    di.category,
    di.label,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid  -- Fixed: direct INT64 join, no CAST
  INNER JOIN vital_itemids vi ON ce.itemid = vi.itemid
  WHERE ce.charttime <= c.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
    AND di.category = 'Vital Signs'
),

vital_stats AS (
  -- Compute mean/stddev per vital category per stay (group by label for finer granularity, e.g., Sys vs Dia BP)
  SELECT 
    stay_id,
    label,
    AVG(valuenum) AS mean_val,
    STDDEV(valuenum) AS std_val
  FROM vitals
  GROUP BY stay_id, label
),

instability_scores AS (
  -- CV per vital type, then average per stay for instability score
  SELECT 
    stay_id,
    AVG(std_val / NULLIF(mean_val, 0) * 100) AS instability_score
  FROM vital_stats
  GROUP BY stay_id
  HAVING COUNT(DISTINCT label) >= 3  -- At least 3 distinct vital types
),

percentiles AS (
  -- Compute score distribution and 90th percentile
  SELECT 
    stay_id,
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS score_percentile,
    PERCENTILE_CONT(0.9) OVER (ORDER BY instability_score) AS p90_threshold
  FROM instability_scores
),

cohort_with_scores AS (
  -- Join scores back to cohort
  SELECT 
    c.*,
    p.instability_score,
    p.score_percentile,
    p.p90_threshold
  FROM cohort c
  INNER JOIN percentiles p ON c.stay_id = p.stay_id
)

-- Final metrics
SELECT 
  -- Percentile for score=75 (using PERCENT_RANK; higher % means more unstable)
  MAX(CASE WHEN instability_score = 75 THEN score_percentile * 100 END) AS percentile_for_75,
  -- If exact 75 not found, approximate as % of stays with score >=75
  (COUNTIF(instability_score >= 75) * 100.0 / COUNT(*)) AS approx_percentile_for_75_or_higher,
  
  -- Top decile (score >= 90th percentile)
  AVG(CASE WHEN instability_score >= p90_threshold THEN los END) AS avg_los_top_decile_days,
  (AVG(CASE WHEN instability_score >= p90_threshold AND hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100) AS mortality_pct_top_decile
FROM cohort_with_scores;