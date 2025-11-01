WITH cohort AS (
  -- Base cohort: male patients 89-99 with first ICU stay
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime, 
    i.los, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 89 AND 99
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime ASC) = 1
),
stroke_cohort AS (
  -- Add stroke flag (any I63 ICD-10 or relevant ICD-9 diagnosis in the admission)
  SELECT 
    c.*,
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I63%') 
             OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
             THEN 1 ELSE 0 END) AS has_stroke
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id
  GROUP BY 
    c.subject_id, c.anchor_age, c.stay_id, c.hadm_id, c.intime, c.outtime, c.los, c.hospital_expire_flag
),
scores AS (
  -- Compute instability score and abnormal episodes per patient/stay
  SELECT 
    sc.*,
    -- Instability score: count of warning=1 events in first 48h
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     WHERE ce.stay_id = sc.stay_id
       AND ce.charttime >= sc.intime
       AND ce.charttime < TIMESTAMP_ADD(sc.intime, INTERVAL 48 HOUR)
       AND ce.warning IS NOT NULL 
       AND ce.warning = 1
    ) AS instability_score,
    -- Abnormal episodes: distinct charttime with at least one warning=1 in first 48h
    (SELECT COUNT(DISTINCT ce.charttime)
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     WHERE ce.stay_id = sc.stay_id
       AND ce.charttime >= sc.intime
       AND ce.charttime < TIMESTAMP_ADD(sc.intime, INTERVAL 48 HOUR)
       AND ce.warning IS NOT NULL 
       AND ce.warning = 1
    ) AS abnormal_episodes
  FROM stroke_cohort sc
),
p95_stroke AS (
  -- 95th percentile instability score for ischemic stroke patients
  SELECT PERCENTILE_CONT(instability_score, 0.95) AS p95_instability_stroke
  FROM scores 
  WHERE has_stroke = 1
),
p75_overall AS (
  -- 75th percentile instability score for entire cohort (for top quartile threshold)
  SELECT PERCENTILE_CONT(instability_score, 0.75) AS p75_instability
  FROM scores
),
top_quartile AS (
  -- Patients in top instability quartile
  SELECT s.*
  FROM scores s
  CROSS JOIN p75_overall p75
  WHERE s.instability_score >= p75.p75_instability
),
comparison AS (
  SELECT 
    CASE WHEN has_stroke = 1 THEN 'Ischemic Stroke' ELSE 'General ICU' END AS cohort_type,
    COUNT(DISTINCT subject_id) AS N,
    AVG(instability_score) AS mean_instability,
    AVG(abnormal_episodes) AS mean_abnormal_episodes,
    AVG(los * 24) AS mean_icu_los_hrs,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM top_quartile
  GROUP BY has_stroke
)
-- Final output: comparison table for top quartile (with p95 only for stroke)
SELECT 
  cohort_type,
  CASE WHEN cohort_type = 'Ischemic Stroke' THEN p95_instability_stroke ELSE NULL END AS p95_instability_score,
  N,
  ROUND(mean_instability, 2) AS mean_instability,
  ROUND(mean_abnormal_episodes, 2) AS mean_abnormal_episodes,
  ROUND(mean_icu_los_hrs, 2) AS mean_icu_los_hrs,
  ROUND(mortality_rate, 4) AS mortality_rate
FROM comparison
CROSS JOIN p95_stroke
ORDER BY CASE WHEN cohort_type = 'Ischemic Stroke' THEN 1 ELSE 2 END;