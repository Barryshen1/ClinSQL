WITH 
-- Target population with AMI and ICU stay
target_population AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    d.drg_severity
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND dd.long_title LIKE '%Acute myocardial infarction%'
),

-- Age-matched general inpatients
age_matched_general AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
    )
)

-- Calculating outcomes for target population
SELECT 
  -- Median risk score (IQR) for target population
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tp.drg_severity) AS median_risk_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tp.drg_severity) AS iqr_25,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tp.drg_severity) AS iqr_75,
  
  -- 90-day mortality for target population
  SUM(CASE 
        WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, tp.admittime) <= 90 THEN 1 
        ELSE 0 
      END) / COUNT(tp.subject_id) AS ninety_day_mortality,
  
  -- Major complication rate and survivor LOS for target population
  SUM(CASE 
        WHEN d.description LIKE '%Complication%' THEN 1 
        ELSE 0 
      END) / COUNT(tp.subject_id) AS major_complication_rate,
  AVG(DATE_DIFF(tp.dischtime, tp.admittime)) AS survivor_los
FROM 
  target_population tp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON tp.subject_id = p.subject_id;

-- Calculating outcomes for age-matched general inpatients
WITH age_matched_general_outcomes AS (
  SELECT 
    -- 90-day mortality for age-matched general
    SUM(CASE 
          WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, amg.admittime) <= 90 THEN 1 
          ELSE 0 
        END) / COUNT(amg.subject_id) AS ninety_day_mortality,
    
    -- Major complication rate and survivor LOS for age-matched general
    SUM(CASE 
          WHEN d.description LIKE '%Complication%' THEN 1 
          ELSE 0 
        END) / COUNT(amg.subject_id) AS major_complication_rate,
    AVG(DATE_DIFF(amg.dischtime, amg.admittime)) AS survivor_los
  FROM 
    age_matched_general amg
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON amg.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` d 
      ON amg.subject_id = d.subject_id AND amg.hadm_id = d.hadm_id
)
SELECT * FROM age_matched_general_outcomes;