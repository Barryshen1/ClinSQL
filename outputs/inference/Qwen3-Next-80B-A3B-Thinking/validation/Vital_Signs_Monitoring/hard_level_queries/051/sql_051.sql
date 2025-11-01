WITH male_89_99 AS (
  SELECT 
    p.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime,  -- Added missing intime column
    i.los, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

abnormal_events AS (
  SELECT 
    c.stay_id, 
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON c.itemid = d.itemid
  JOIN male_89_99 m 
    ON c.stay_id = m.stay_id
  WHERE c.valuenum IS NOT NULL
    AND (c.valuenum < d.lownormalvalue OR c.valuenum > d.highnormalvalue)
    AND c.charttime BETWEEN m.intime AND DATETIME_ADD(m.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),

instability_scores AS (
  SELECT 
    m.subject_id, 
    m.hadm_id, 
    m.stay_id, 
    m.los, 
    m.hospital_expire_flag,
    COALESCE(a.abnormal_count, 0) AS instability_score
  FROM male_89_99 m
  LEFT JOIN abnormal_events a 
    ON m.stay_id = a.stay_id
),

ischemic_stroke AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%'))
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
),

stroke_patients AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.los, 
    i.hospital_expire_flag, 
    i.instability_score,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_stroke
  FROM instability_scores i
  LEFT JOIN ischemic_stroke s 
    ON i.hadm_id = s.hadm_id
),

ninety_fifth_percentile AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.95) WITHIN GROUP (ORDER BY instability_score) AS ninety_fifth_percentile
  FROM stroke_patients
  WHERE is_stroke = 1
),

top_quartile AS (
  SELECT *
  FROM stroke_patients
  WHERE instability_score >= (
    SELECT PERCENTILE_CONT(instability_score, 0.75) WITHIN GROUP (ORDER BY instability_score) 
    FROM stroke_patients
  )
)

SELECT ninety_fifth_percentile FROM ninety_fifth_percentile

UNION ALL

SELECT 
  'ischemic_stroke' AS group_type,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score) AS mean_abnormal_episodes,
  AVG(los * 24) AS mean_icu_los_hours,
  AVG(hospital_expire_flag) AS mortality
FROM top_quartile
WHERE is_stroke = 1

UNION ALL

SELECT 
  'non_stroke' AS group_type,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(instability_score) AS mean_abnormal_episodes,
  AVG(los * 24) AS mean_icu_los_hours,
  AVG(hospital_expire_flag) AS mortality
FROM top_quartile
WHERE is_stroke = 0;