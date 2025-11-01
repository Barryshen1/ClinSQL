WITH cohort AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON i.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dicd.long_title) LIKE '%respiratory failure%'
),

vital_events AS (
  SELECT 
    i.stay_id,
    SUM(CASE WHEN di.label = 'MAP' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_episodes,
    SUM(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce ON i.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE ce.charttime >= i.intime 
    AND ce.charttime <= i.intime + INTERVAL '48' HOUR
    AND di.label IN ('MAP', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY i.stay_id
),

vii AS (
  SELECT 
    c.stay_id,
    COALESCE(ve.map_low_episodes, 0) + COALESCE(ve.tachycardia_episodes, 0) AS vital_instability_index
  FROM cohort c
  LEFT JOIN vital_events ve ON c.stay_id = ve.stay_id
),

percentiles AS (
  SELECT 
    PERCENTILE_CONT(vii.vital_instability_index, 0.75) AS p75,
    PERCENTILE_CONT(vii.vital_instability_index, 0.95) AS p95
  FROM vii
),

top_quartile AS (
  SELECT v.stay_id
  FROM vii v
  CROSS JOIN percentiles p
  WHERE v.vital_instability_index >= p.p75
),

general_icu AS (
  SELECT 
    i.stay_id,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
)

SELECT 
  'Top Quartile (Respiratory Failure Cohort)' AS group_name,
  AVG(CASE WHEN tq.stay_id IS NOT NULL THEN ve.map_low_episodes ELSE NULL END) AS avg_map_low_episodes,
  AVG(CASE WHEN tq.stay_id IS NOT NULL THEN ve.tachycardia_episodes ELSE NULL END) AS avg_tachycardia_episodes,
  AVG(CASE WHEN tq.stay_id IS NOT NULL THEN gi.los ELSE NULL END) AS avg_icu_los,
  AVG(CASE WHEN tq.stay_id IS NOT NULL THEN gi.hospital_expire_flag ELSE NULL END) AS mortality_rate
FROM general_icu gi
LEFT JOIN vital_events ve ON gi.stay_id = ve.stay_id
LEFT JOIN top_quartile tq ON gi.stay_id = tq.stay_id

UNION ALL

SELECT 
  'General ICU Population' AS group_name,
  AVG(ve.map_low_episodes) AS avg_map_low_episodes,
  AVG(ve.tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(gi.los) AS avg_icu_los,
  AVG(gi.hospital_expire_flag) AS mortality_rate
FROM general_icu gi
INNER JOIN vital_events ve ON gi.stay_id = ve.stay_id;