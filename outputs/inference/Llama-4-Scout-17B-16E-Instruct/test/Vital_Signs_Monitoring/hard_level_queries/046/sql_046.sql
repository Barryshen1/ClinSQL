WITH 
-- Identify ischemic stroke patients
ischemic_stroke_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Ischemic stroke%'
),

-- Identify relevant ICU patients
icu_patients AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN ischemic_stroke_patients isp ON i.subject_id = isp.subject_id AND i.hadm_id = isp.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 84 AND 94
),

-- Calculate vital sign instability score (example: heart rate, blood pressure)
vital_signs AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    charttime,
    -- Example calculation for heart rate and blood pressure instability
    CASE 
      WHEN itemid = 220050 AND valuenum > 100 THEN 1 
      WHEN itemid = 220179 AND valuenum > 180 THEN 1 
      ELSE 0 
    END AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid IN (220050, 220179)  -- Heart rate and Systolic blood pressure
),

-- Calculate first 72 hours vital sign instability score
instability_scores AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    SUM(instability_score) AS total_instability_score
  FROM vital_signs
  WHERE charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
  GROUP BY subject_id, hadm_id, stay_id
),

-- Calculate ICU LOS and mortality
icu_outcomes AS (
  SELECT 
    i.stay_id,
    i.los AS icu_los,
    CASE 
      WHEN p.dod IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
),

-- Calculate percentile of instability scores
percentile_q1 AS (
  SELECT 
    APPROX_QUANTILES(total_instability_score, 0.25) AS q1_instability_score
  FROM instability_scores
)

-- Final query
SELECT 
  p.q1_instability_score,
  AVG(CASE WHEN is_.total_instability_score <= p.q1_instability_score[OFFSET(0)] THEN io.icu_los END) AS avg_icu_los_q1,
  AVG(CASE WHEN is_.total_instability_score <= p.q1_instability_score[OFFSET(0)] THEN io.mortality END) AS avg_mortality_q1
FROM percentile_q1 p
CROSS JOIN instability_scores AS is_
JOIN icu_outcomes io ON is_.stay_id = io.stay_id;