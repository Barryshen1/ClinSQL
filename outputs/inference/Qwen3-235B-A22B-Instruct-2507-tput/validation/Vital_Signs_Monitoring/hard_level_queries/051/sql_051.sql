WITH patient_stay AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los AS icu_los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 89 AND 99
),
stroke_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (di.icd_version = 10 AND d.icd_code LIKE 'I63%')
     OR (di.icd_version = 9 AND d.icd_code IN ('43401', '43411'))  -- Note: ICD-9 codes in MIMIC are stored without dots
),
cohort AS (
  SELECT 
    ps.*,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ischemic_stroke
  FROM patient_stay ps
  LEFT JOIN stroke_diagnoses sd ON ps.hadm_id = sd.hadm_id
),
instability_metrics AS (
  SELECT 
    c.stay_id,
    c.hadm_id,
    c.ischemic_stroke,
    c.icu_los_days,
    c.hospital_expire_flag,
    COUNT(DISTINCT ce.itemid) AS instability_score,  -- distinct vitals/measurements in first 48h
    COUNTIF(ce.warning = 1) AS abnormal_episodes
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce 
    ON c.stay_id = ce.stay_id 
    AND ce.charttime >= c.intime 
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.value IS NOT NULL  -- valid measurements only
  GROUP BY c.stay_id, c.hadm_id, c.ischemic_stroke, c.icu_los_days, c.hospital_expire_flag
),
instability_percentiles AS (
  SELECT
    ischemic_stroke,
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_instability
  FROM instability_metrics
  WHERE ischemic_stroke = 1
  LIMIT 1
),
overall_stats AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM instability_metrics
),
top_quartile AS (
  SELECT *
  FROM overall_stats
  WHERE instability_quartile = 1  -- top 25% most unstable
)
SELECT
  'ischemic_stroke' AS group_type,
  ischemic_stroke,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(abnormal_episodes) AS mean_abnormal_episodes,
  AVG(icu_los_days * 24) AS mean_icu_los_hours,
  AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile
GROUP BY ischemic_stroke

UNION ALL

SELECT
  '95th_percentile_instability' AS group_type,
  CAST(NULL AS INT64) AS ischemic_stroke,
  CAST(NULL AS INT64) AS N,
  p95_instability AS mean_instability,
  CAST(NULL AS FLOAT64) AS mean_abnormal_episodes,
  CAST(NULL AS FLOAT64) AS mean_icu_los_hours,
  CAST(NULL AS FLOAT64) AS mortality_rate
FROM instability_percentiles
;