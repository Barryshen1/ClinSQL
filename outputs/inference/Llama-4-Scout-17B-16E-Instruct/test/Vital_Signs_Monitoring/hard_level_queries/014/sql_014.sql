WITH 
-- Identify male patients aged 88-98
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 88 AND 98
),

-- Combine icustays with chartevents for instability score calculation
icustay_chartevents AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    i.intime,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.subject_id = ce.subject_id AND i.hadm_id = ce.hadm_id
),

-- Assume instability score calculation is based on chartevents within the first 72 hours
instability_scores AS (
  SELECT 
    subject_id, 
    hadm_id, 
    -- Simplified example: assume we calculate instability score as average of certain itemids
    AVG(CASE WHEN itemid IN (some_itemid1, some_itemid2) THEN valuenum ELSE NULL END) AS instability_score
  FROM 
    icustay_chartevents
  WHERE 
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Combine eligible patients with instability scores
patient_scores AS (
  SELECT 
    ep.subject_id, 
    ep.hadm_id, 
    isc.instability_score
  FROM 
    eligible_patients ep
  JOIN 
    instability_scores isc ON ep.subject_id = isc.subject_id AND ep.hadm_id = isc.hadm_id
),

-- Calculate percentile of instability score 85
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 1000)[85] AS percentile_85
  FROM 
    patient_scores
),

-- Identify most unstable quartile
unstable_quartile AS (
  SELECT 
    subject_id, 
    hadm_id, 
    instability_score,
    ICU_LOS,
    hospital_mortality
  FROM (
    SELECT 
      ps.subject_id, 
      ps.hadm_id, 
      ps.instability_score,
      i.los AS ICU_LOS,
      CASE WHEN a.hospital_expire_flag = 1 THEN TRUE ELSE FALSE END AS hospital_mortality,
      NTILE(4) OVER (ORDER BY ps.instability_score) AS quartile
    FROM 
      patient_scores ps
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i ON ps.subject_id = i.subject_id AND ps.hadm_id = i.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON ps.subject_id = a.subject_id AND ps.hadm_id = a.hadm_id
  ) subquery
  WHERE quartile = 4
)

-- Final output
SELECT 
  (SELECT percentile_85 FROM percentile_score) AS percentile_85,
  AVG(ICU_LOS) AS avg_ICU_LOS,
  AVG(CASE WHEN hospital_mortality THEN 1 ELSE 0 END) AS hospital_mortality_rate
FROM 
  unstable_quartile;