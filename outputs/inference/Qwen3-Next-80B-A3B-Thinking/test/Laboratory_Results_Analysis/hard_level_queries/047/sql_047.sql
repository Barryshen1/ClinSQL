WITH ards_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON d.subject_id = p.subject_id
  WHERE d.icd_code = 'J80' AND d.icd_version = 10
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),
ards_icu AS (
  SELECT a.subject_id, a.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM ards_patients a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),
vitals AS (
  SELECT 
    i.stay_id,
    i.intime,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM ards_icu i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    AND c.itemid IN (220045, 220050)
),
instability_events AS (
  SELECT 
    stay_id,
    SUM(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END) +
    SUM(CASE WHEN itemid = 220050 AND valuenum < 90 THEN 1 ELSE 0 END) AS instability_score
  FROM vitals
  GROUP BY stay_id
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS threshold
  FROM instability_events
),
high_instability AS (
  SELECT 
    ie.stay_id,
    ie.instability_score,
    a.hospital_expire_flag,
    i.los
  FROM instability_events ie
  JOIN ards_icu i ON ie.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  CROSS JOIN percentile p
  WHERE ie.instability_score >= p.threshold
),
high_instability_hadm AS (
  SELECT DISTINCT hadm_id
  FROM high_instability
  JOIN ards_icu ON high_instability.stay_id = ards_icu.stay_id
),
critical_labs AS (
  SELECT 
    'high_instability' AS group_name,
    COUNT(DISTINCT CASE WHEN l.valuenum > 5.0 THEN l.subject_id END) * 1.0 / COUNT(DISTINCT l.subject_id) AS potassium_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN high_instability_hadm hi ON l.hadm_id = hi.hadm_id
  WHERE l.itemid = 50971
),
general_labs AS (
  SELECT 
    'general_inpatients' AS group_name,
    COUNT(DISTINCT CASE WHEN l.valuenum > 5.0 THEN l.subject_id END) * 1.0 / COUNT(DISTINCT l.subject_id) AS potassium_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50971
),
mortality_los AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate,
    AVG(los) AS mean_los
  FROM high_instability
)
SELECT 
  m.mortality_rate,
  m.mean_los,
  c.potassium_rate AS high_instability_kpotassium,
  g.potassium_rate AS general_kpotassium
FROM mortality_los m
CROSS JOIN critical_labs c
CROSS JOIN general_labs g;