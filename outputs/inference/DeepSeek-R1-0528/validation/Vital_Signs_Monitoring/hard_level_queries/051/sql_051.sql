WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    adm.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
),
cohort_age_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_at_icu BETWEEN 89 AND 99
),
stroke_flag AS (
  SELECT 
    hadm_id,
    1 AS ischemic_stroke_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'I63%') 
    OR 
    (icd_version = 9 AND icd_code IN (
      '43301','43311','43321','43331','43381','43391',
      '43401','43411','43491','436'
    ))
),
cohort_with_stroke AS (
  SELECT 
    c.*,
    COALESCE(sf.ischemic_stroke_flag, 0) AS ischemic_stroke_flag
  FROM cohort_age_filtered c
  LEFT JOIN stroke_flag sf
    ON c.hadm_id = sf.hadm_id
),
lab_abnormal AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS instability_score,
    COUNT(DISTINCT le.charttime) AS abnormal_episodes
  FROM cohort_with_stroke c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.intime
    AND le.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY c.stay_id
),
full_cohort AS (
  SELECT 
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.ischemic_stroke_flag,
    COALESCE(l.instability_score, 0) AS instability_score,
    COALESCE(l.abnormal_episodes, 0) AS abnormal_episodes,
    c.los * 24 AS icu_los_hrs,
    c.hospital_expire_flag
  FROM cohort_with_stroke c
  LEFT JOIN lab_abnormal l
    ON c.stay_id = l.stay_id
),
percentile_95_stroke AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS ischemic_stroke_95th_percentile
  FROM full_cohort
  WHERE ischemic_stroke_flag = 1
  LIMIT 1
),
percentile_75_all AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS percentile_75
  FROM full_cohort
  LIMIT 1
),
top_quartile_cohort AS (
  SELECT 
    fc.*
  FROM full_cohort fc
  CROSS JOIN percentile_75_all p75
  WHERE fc.instability_score >= p75.percentile_75
)
-- Part 1: 95th percentile for ischemic stroke
SELECT 
  'Part1: 95th Percentile for Ischemic Stroke' AS description,
  ischemic_stroke_95th_percentile AS value,
  NULL AS group_name,
  NULL AS N,
  NULL AS mean_instability,
  NULL AS mean_abnormal_episodes,
  NULL AS mean_icu_los_hrs,
  NULL AS mortality_rate
FROM percentile_95_stroke

UNION ALL

-- Part 2: Top quartile comparison (Ischemic Stroke vs. General ICU)
SELECT 
  'Part2: Top Quartile Comparison' AS description,
  NULL AS value,
  CASE 
    WHEN ischemic_stroke_flag = 1 THEN 'Ischemic Stroke' 
    ELSE 'General ICU' 
  END AS group_name,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(abnormal_episodes) AS mean_abnormal_episodes,
  AVG(icu_los_hrs) AS mean_icu_los_hrs,
  AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile_cohort
GROUP BY group_name;