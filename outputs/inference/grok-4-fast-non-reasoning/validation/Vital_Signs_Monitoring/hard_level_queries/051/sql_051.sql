WITH base_cohort AS (
  -- Male ICU patients aged 89-99
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND i.los > 0  -- Valid ICU stays
),

stroke_cohort AS (
  -- Add ischemic stroke filter (primary dx I63*)
  SELECT 
    bc.*,
    CASE WHEN di.icd_code LIKE 'I63%' AND di.seq_num = 1 THEN 1 ELSE 0 END AS has_stroke
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON bc.hadm_id = di.hadm_id
    AND di.icd_version = '10'  -- ICD-10 for I63
),

vital_itemids AS (
  -- Vital signs for instability (HR, RR, SysBP, DiasBP, Temp, SpO2)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE itemid IN (220045, 220210, 220179, 220180, 223761, 220277)
),

instability_scores AS (
  -- Calculate 48h abnormal episodes per stay (distinct timestamps)
  SELECT 
    sc.stay_id,
    sc.has_stroke,
    sc.intime,
    sc.los,
    sc.hospital_expire_flag,
    COUNT(DISTINCT TIMESTAMP_TRUNC(ce.charttime, HOUR)) AS instability_score  -- Hourly episodes of abnormality
  FROM stroke_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON sc.stay_id = ce.stay_id
  INNER JOIN vital_itemids vi
    ON ce.itemid = vi.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime <= sc.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
    AND (ce.valuenum < SAFE_CAST(di.lownormalvalue AS FLOAT64) OR ce.valuenum > SAFE_CAST(di.highnormalvalue AS FLOAT64))  -- Abnormal
    AND di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NOT NULL  -- Valid ranges
  GROUP BY sc.stay_id, sc.has_stroke, sc.intime, sc.los, sc.hospital_expire_flag
),

-- 95th percentile for stroke cohort
p95_stroke AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability
  FROM instability_scores
  WHERE has_stroke = 1
),

-- Top quartile thresholds (separate for stroke and general)
q75_stroke AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75_stroke
  FROM instability_scores
  WHERE has_stroke = 1
),
q75_general AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75_general
  FROM instability_scores
  WHERE has_stroke = 0
),

-- Top quartile subsets
top_quartile_stroke AS (
  SELECT *
  FROM instability_scores
  CROSS JOIN q75_stroke
  WHERE has_stroke = 1 AND instability_score >= q75_stroke
),

top_quartile_general AS (
  SELECT *
  FROM instability_scores
  CROSS JOIN q75_general
  WHERE has_stroke = 0 AND instability_score >= q75_general
)

-- Part 1: 95th percentile for stroke
SELECT 
  'Ischemic Stroke 95th Percentile Instability Score' AS metric,
  ANY_VALUE(p95_instability) AS value
FROM p95_stroke

UNION ALL

-- Part 2: Top quartile comparison
SELECT 
  'Top Quartile Ischemic Stroke' AS cohort,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score) AS mean_abnormal_episodes,  -- Same as instability (episodes)
  AVG(los) AS mean_icu_los_hrs,
  AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_proportion
FROM top_quartile_stroke

UNION ALL

SELECT 
  'Top Quartile General ICU' AS cohort,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score) AS mean_abnormal_episodes,
  AVG(los) AS mean_icu_los_hrs,
  AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_proportion
FROM top_quartile_general;