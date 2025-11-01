WITH 
-- Define ICH ICD codes
ich_diagnoses AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '907.0%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'
),

-- Filter patients and calculate vital-sign instability score
patients_with_ich AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d.icd_code IN (SELECT icd_code FROM ich_diagnoses)
),

-- Simplified vital-sign instability score calculation (example)
vital_sign_scores AS (
  SELECT 
    subject_id,
    stay_id,
    -- Example calculation: average of heart rate and blood pressure variability
    AVG(CASE 
          WHEN itemid = 220050 THEN valuenum 
          ELSE NULL 
        END) AS heart_rate,
    AVG(CASE 
          WHEN itemid = 220179 THEN valuenum 
          ELSE NULL 
        END) AS systolic_blood_pressure
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    charttime BETWEEN intime AND intime + INTERVAL 3 DAY
  GROUP BY 
    subject_id, stay_id
),

-- Calculate instability score (example)
instability_scores AS (
  SELECT 
    subject_id,
    stay_id,
    -- Example instability score calculation
    (heart_rate + systolic_blood_pressure) / 2 AS instability_score,
    los,
    hospital_expire_flag
  FROM 
    patients_with_ich
  JOIN 
    vital_sign_scores ON patients_with_ich.subject_id = vital_sign_scores.subject_id AND patients_with_ich.stay_id = vital_sign_scores.stay_id
)

-- Calculate instability score and percentile
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY instability_score) AS percentile_75,
  AVG(CASE WHEN instability_score >= PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_score) 
             THEN los END) AS avg_los_top_decile,
  SUM(CASE WHEN hospital_expire_flag = 1 AND instability_score >= PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_score) 
             THEN 1 ELSE 0 END) / COUNT(CASE WHEN instability_score >= PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_score) 
             THEN subject_id END) AS mortality_top_decile
FROM 
  instability_scores;