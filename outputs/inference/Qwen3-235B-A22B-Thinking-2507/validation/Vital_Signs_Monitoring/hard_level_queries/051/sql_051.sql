WITH admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
general_icu AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    a.admittime,
    i.intime,
    i.outtime,
    a.hospital_expire_flag
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE a.gender = 'M'
    AND a.age BETWEEN 89 AND 99
),
stroke_diagnoses AS (
  SELECT 
    hadm_id,
    TRUE AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '434%')
     OR (icd_version = 10 AND icd_code LIKE 'I63%')
  GROUP BY hadm_id
),
general_icu_with_stroke AS (
  SELECT 
    g.*,
    COALESCE(s.has_stroke, FALSE) AS is_stroke
  FROM general_icu g
  LEFT JOIN stroke_diagnoses s
    ON g.hadm_id = s.hadm_id
),
instability_scores AS (
  SELECT 
    g.stay_id,
    g.subject_id,
    g.hadm_id,
    g.intime,
    g.outtime,
    g.hospital_expire_flag,
    g.is_stroke,
    COUNT(*) AS instability_score
  FROM general_icu_with_stroke g
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON g.stay_id = ce.stay_id
    AND ce.charttime BETWEEN g.intime AND g.intime + INTERVAL '48' HOUR
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.category IN (
      'Heart Rate',
      'Respiratory Rate',
      'Non-Invasive Blood Pressure',
      'Temperature',
      'O2 saturation pulseoxymetry'
    )
    AND ce.valuenum IS NOT NULL
    AND di.lownormalvalue IS NOT NULL
    AND di.highnormalvalue IS NOT NULL
    AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)
  GROUP BY g.stay_id, g.subject_id, g.hadm_id, g.intime, g.outtime, g.hospital_expire_flag, g.is_stroke
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile_general,
    NTILE(4) OVER (PARTITION BY is_stroke ORDER BY instability_score DESC) AS quartile_stroke
  FROM instability_scores
)
-- Part 1: 95th percentile for ischemic stroke group
SELECT 
  '95th_percentile_ischemic_stroke' AS group_type,
  CAST(NULL AS INT64) AS N,
  p95 AS mean_instability,
  CAST(NULL AS FLOAT64) AS mean_abnormal_episodes,
  CAST(NULL AS FLOAT64) AS mean_los_hours,
  CAST(NULL AS FLOAT64) AS mortality
FROM (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95
  FROM instability_scores
  WHERE is_stroke = TRUE
)

UNION ALL

-- Part 2: Ischemic stroke top quartile
SELECT 
  'ischemic stroke' AS group_type,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score / 48.0) AS mean_abnormal_episodes,
  AVG(TIMESTAMP_DIFF(outtime, intime, SECOND) / 3600.0) AS mean_los_hours,
  AVG(hospital_expire_flag) AS mortality
FROM quartiles
WHERE is_stroke = TRUE AND quartile_stroke = 1

UNION ALL

-- Part 2: General ICU top quartile
SELECT 
  'general ICU' AS group_type,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score / 48.0) AS mean_abnormal_episodes,
  AVG(TIMESTAMP_DIFF(outtime, intime, SECOND) / 3600.0) AS mean_los_hours,
  AVG(hospital_expire_flag) AS mortality
FROM quartiles
WHERE quartile_general = 1;