WITH 
-- Filter icustays for male patients aged 81-91
filtered_icustays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime, 
    ie.outtime, 
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 81 AND 91
),

-- Identify HFNC usage in the first 48 hours
hfnc_usage AS (
  SELECT DISTINCT
    ce.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    filtered_icustays fi 
  ON 
    ce.stay_id = fi.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
  ON 
    ce.itemid = di.itemid
  WHERE 
    (di.label LIKE '%High Flow Nasal Cannula%' 
    OR di.label LIKE '%HFNC%')
  AND ce.charttime BETWEEN fi.intime AND TIMESTAMP_ADD(fi.intime, INTERVAL 48 HOUR)
),

-- Calculate composite instability score (example; actual calculation may vary)
instability_scores AS (
  SELECT 
    fi.stay_id, 
    -- Example score calculation; replace with actual logic
    SUM(ce.valuenum) AS composite_score
  FROM 
    filtered_icustays fi
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
  ON 
    fi.stay_id = ce.stay_id
  WHERE 
    ce.charttime BETWEEN fi.intime AND TIMESTAMP_ADD(fi.intime, INTERVAL 48 HOUR)
  GROUP BY 
    fi.stay_id
),

-- Calculate percentile, average ICU LOS, and hospital mortality for top decile
analysis AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY `is`.composite_score) AS score_percentile,
    fi.stay_id,
    TIMESTAMP_DIFF(fi.outtime, fi.intime, HOUR) / 24.0 AS icu_los_days,
    h.hospital_expire_flag
  FROM 
    instability_scores `is`
  INNER JOIN 
    filtered_icustays fi 
  ON 
    `is`.stay_id = fi.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` h 
  ON 
    fi.hadm_id = h.hadm_id
  WHERE 
    fi.stay_id IN (SELECT stay_id FROM hfnc_usage)
)

SELECT 
  -- Percentile for a score of 85
  (SELECT COUNT(*) FROM analysis WHERE score_percentile <= (SELECT score_percentile FROM analysis WHERE composite_score = 85)) / (SELECT COUNT(*) FROM analysis) AS percentile_85,
  -- Average ICU LOS for top decile
  AVG(icu_los_days) AS avg_icu_los_top_decile,
  -- Hospital mortality for top decile
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_top_decile
FROM 
  analysis
WHERE 
  score_percentile >= 0.9;