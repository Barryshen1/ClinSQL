WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, p.gender, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ie.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
  AND dicd.long_title LIKE '%Heart failure%'
),

-- Step 2: Calculate the 72h composite instability score
instability_score AS (
  SELECT ce.stay_id, 
         SUM(CASE WHEN di.label LIKE '%Heart Rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
         SUM(CASE WHEN di.label LIKE '%Invasive Blood Pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65_count,
         SUM(CASE WHEN di.label LIKE '%Respiratory Rate%' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.stay_id IN (SELECT stay_id FROM cohort)
  AND ce.charttime BETWEEN (SELECT MIN(intime) FROM cohort WHERE stay_id = ce.stay_id) AND TIMESTAMP_ADD((SELECT MIN(intime) FROM cohort WHERE stay_id = ce.stay_id), INTERVAL 3 DAY)
  GROUP BY ce.stay_id
),

-- Step 3: Calculate composite instability score and its 99th percentile
composite_score AS (
  SELECT stay_id, (tachycardia_count + map_lt_65_count + tachypnea_count) AS instability_score
  FROM instability_score
),
percentile_99 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(99)] AS percentile_99
  FROM composite_score
),

-- Step 4: Identify the most unstable quartile
quartile_scores AS (
  SELECT stay_id, instability_score,
         NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM composite_score
),
most_unstable AS (
  SELECT stay_id
  FROM quartile_scores
  WHERE quartile = 4
),

-- Step 5: Comparative analysis for the most unstable quartile vs overall ICU population
comparative_analysis AS (
  SELECT 
    'Most Unstable' AS group_name,
    AVG(CASE WHEN di.label LIKE '%Heart Rate%' AND ce.valuenum > 100 THEN 1.0 ELSE 0 END) AS avg_tachycardia,
    AVG(CASE WHEN di.label LIKE '%Invasive Blood Pressure%' AND ce.valuenum < 65 THEN 1.0 ELSE 0 END) AS avg_map_lt_65,
    AVG(CASE WHEN di.label LIKE '%Respiratory Rate%' AND ce.valuenum > 20 THEN 1.0 ELSE 0 END) AS avg_tachypnea,
    AVG(TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR)/24.0) AS avg_icu_los,
    AVG(CASE WHEN ie.outtime = ad.deathtime THEN 1.0 ELSE 0 END) AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON ie.hadm_id = ad.hadm_id
  WHERE ce.stay_id IN (SELECT stay_id FROM most_unstable)
  GROUP BY 'Most Unstable'
  UNION ALL
  SELECT 
    'Overall ICU' AS group_name,
    AVG(CASE WHEN di.label LIKE '%Heart Rate%' AND ce.valuenum > 100 THEN 1.0 ELSE 0 END) AS avg_tachycardia,
    AVG(CASE WHEN di.label LIKE '%Invasive Blood Pressure%' AND ce.valuenum < 65 THEN 1.0 ELSE 0 END) AS avg_map_lt_65,
    AVG(CASE WHEN di.label LIKE '%Respiratory Rate%' AND ce.valuenum > 20 THEN 1.0 ELSE 0 END) AS avg_tachypnea,
    AVG(TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR)/24.0) AS avg_icu_los,
    AVG(CASE WHEN ie.outtime = ad.deathtime THEN 1.0 ELSE 0 END) AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON ie.hadm_id = ad.hadm_id
  WHERE ce.stay_id IN (SELECT stay_id FROM cohort)
  GROUP BY 'Overall ICU'
)

-- Final query to get the 99th percentile and comparative analysis
SELECT 
  (SELECT percentile_99 FROM percentile_99) AS percentile_99,
  ca.*
FROM comparative_analysis ca;