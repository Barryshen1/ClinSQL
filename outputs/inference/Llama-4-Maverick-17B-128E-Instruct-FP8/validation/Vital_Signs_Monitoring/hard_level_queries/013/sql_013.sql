WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND ie.intime = (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2 WHERE ie2.subject_id = ie.subject_id)
    AND ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE dicd.long_title LIKE '%trauma%' 
        AND di.icd_version = 10  -- Assuming ICD-10; adjust as needed
    )
),

-- Step 2: Calculate vital-sign instability scores within the first 24 hours
vital_signs AS (
  SELECT ce.stay_id, 
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS max_hr,
         MIN(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS min_hr,
         MAX(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum ELSE NULL END) AS max_sbp,
         MIN(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum ELSE NULL END) AS min_sbp,
         MAX(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum ELSE NULL END) AS max_rr,
         MIN(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum ELSE NULL END) AS min_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN cohort c ON ce.stay_id = c.stay_id
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Respiratory Rate')
  GROUP BY ce.stay_id
),

-- Calculate instability score (example, actual calculation may vary based on definition)
instability_scores AS (
  SELECT stay_id,
         -- Example score calculation; adjust according to actual definition
         (max_hr - min_hr) + (max_sbp - min_sbp) + (max_rr - min_rr) AS score
  FROM vital_signs
),

-- Step 3: Stratify scores into quartiles and top decile
quartiles AS (
  SELECT stay_id, score,
         NTILE(4) OVER (ORDER BY score) AS quartile,
         PERCENT_RANK() OVER (ORDER BY score) AS percent_rank
  FROM instability_scores
),

-- Calculate episode counts for top decile
episode_counts AS (
  SELECT q.stay_id,
         COUNT(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 END) AS tachycardia_episodes,
         COUNT(CASE WHEN di.label = 'Systolic Blood Pressure' AND ce.valuenum < 90 THEN 1 END) AS hypotension_episodes,
         COUNT(CASE WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 24 THEN 1 END) AS tachypnea_episodes
  FROM quartiles q
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON q.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN (SELECT intime FROM cohort WHERE stay_id = q.stay_id) AND TIMESTAMP_ADD((SELECT intime FROM cohort WHERE stay_id = q.stay_id), INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Respiratory Rate')
  GROUP BY q.stay_id
),

-- Final aggregation
final AS (
  SELECT 
    q.quartile,
    COUNT(*) AS count,
    AVG(q.score) AS mean_score,
    AVG(ie.los) AS mean_icu_los,
    SUM(CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality,
    -- For top decile
    AVG(CASE WHEN q.percent_rank >= 0.9 THEN ec.tachycardia_episodes ELSE NULL END) AS mean_tachycardia_episodes,
    AVG(CASE WHEN q.percent_rank >= 0.9 THEN ec.hypotension_episodes ELSE NULL END) AS mean_hypotension_episodes,
    AVG(CASE WHEN q.percent_rank >= 0.9 THEN ec.tachypnea_episodes ELSE NULL END) AS mean_tachypnea_episodes
  FROM quartiles q
  JOIN cohort c ON q.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON c.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
  JOIN episode_counts ec ON q.stay_id = ec.stay_id
  GROUP BY q.quartile
)

SELECT * FROM final
ORDER BY quartile;