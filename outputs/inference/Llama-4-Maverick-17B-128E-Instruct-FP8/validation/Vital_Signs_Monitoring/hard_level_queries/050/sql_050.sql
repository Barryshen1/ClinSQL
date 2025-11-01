WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    p.anchor_age,
    p.gender,
    ie.intime,
    ie.outtime,
    ie.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
    AND ie.stay_id IN (
      SELECT stay_id 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
      WHERE di.label LIKE '%renal replacement therapy%' 
        AND pe.starttime <= ie.intime + INTERVAL 72 HOUR
    )
),

-- Step 2: Calculate the first-72-hour vital-sign instability score
vital_signs AS (
  SELECT 
    stay_id,
    -- Example vital signs; actual calculation may vary based on definition
    MAX(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum END) AS max_hr,
    MIN(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum END) AS min_hr,
    MAX(CASE WHEN di.label LIKE '%Systolic Blood Pressure%' THEN ce.valuenum END) AS max_sbp,
    MIN(CASE WHEN di.label LIKE '%Systolic Blood Pressure%' THEN ce.valuenum END) AS min_sbp,
    -- Add other vital signs as needed
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    ce.stay_id IN (SELECT stay_id FROM cohort)
    AND ce.charttime BETWEEN (SELECT MIN(intime) FROM cohort WHERE stay_id = ce.stay_id) AND (SELECT MIN(intime) FROM cohort WHERE stay_id = ce.stay_id) + INTERVAL 72 HOUR
  GROUP BY 
    stay_id
),

instability_score AS (
  SELECT 
    stay_id,
    -- Simplified example; actual formula may be more complex
    (max_hr - min_hr) + (max_sbp - min_sbp) AS score
  FROM 
    vital_signs
),

-- Step 3 & 4: Determine percentile and report statistics for top decile
percentile_and_stats AS (
  SELECT 
    ie.stay_id,  
    score,
    PERCENT_RANK() OVER (ORDER BY score) AS percentile,
    los,
    CASE WHEN p.dod IS NOT NULL AND p.dod <= ie.outtime THEN 1 ELSE 0 END AS mortality
  FROM 
    instability_score isc
  INNER JOIN 
    cohort ie ON isc.stay_id = ie.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
)

SELECT 
  -- Percentile of a score of 65
  IFNULL(SAFE_DIVIDE(
    (SELECT COUNT(*) FROM percentile_and_stats WHERE percentile <= (SELECT percentile FROM percentile_and_stats WHERE score <= 65 ORDER BY percentile DESC LIMIT 1)),
    (SELECT COUNT(*) FROM percentile_and_stats)
  ), 0) AS percentile_of_65,
  -- Mean ICU LOS for top decile
  IFNULL(AVG(los), 0) AS mean_los_top_decile,
  -- Mortality for top decile
  IFNULL(AVG(mortality), 0) AS mortality_top_decile
FROM 
  percentile_and_stats
WHERE 
  percentile >= 0.9;