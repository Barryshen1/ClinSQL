WITH 
  -- Target population: Male ICU patients aged 79–89 with pulmonary embolism
  target_population AS (
    SELECT 
      ic.subject_id, 
      ic.hadm_id, 
      ic.stay_id, 
      p.anchor_age, 
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ic.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.hadm_id = di.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 79 AND 89
      AND di.icd_code IN ('415.11', 'I26.0', 'I26.1', 'I26.2', 'I26.3', 'I26.4', 'I26.5', 'I26.6', 'I26.7', 'I26.8', 'I26.9')  -- ICD codes for pulmonary embolism
  ),
  
  -- General ICU population
  general_icu_population AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Target population diagnoses
  target_diagnoses AS (
    SELECT 
      tp.subject_id, 
      COUNT(DISTINCT di.icd_code) AS num_diagnoses
    FROM 
      target_population tp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON tp.hadm_id = di.hadm_id
    GROUP BY 
      tp.subject_id
  ),
  
  -- General ICU population diagnoses
  general_icu_diagnoses AS (
    SELECT 
      gip.hadm_id,
      COUNT(DISTINCT di.icd_code) AS num_diagnoses
    FROM 
      general_icu_population gip
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON gip.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.hadm_id = di.hadm_id
    GROUP BY 
      gip.hadm_id
  )

SELECT 
  'Target Population' AS population,
  APPROX_QUANTILES(td.num_diagnoses, 0.75) AS percentile_75_diagnoses,
  AVG(ic.los) AS avg_icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
FROM 
  target_population tp
JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON tp.stay_id = ic.stay_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON tp.hadm_id = a.hadm_id
JOIN 
  target_diagnoses td 
    ON tp.subject_id = td.subject_id

UNION ALL

SELECT 
  'General ICU Population' AS population,
  APPROX_QUANTILES(gid.num_diagnoses, 0.75) AS percentile_75_diagnoses,
  AVG(ic.los) AS avg_icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
FROM 
  general_icu_population gip
JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON gip.stay_id = ic.stay_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON gip.hadm_id = a.hadm_id
JOIN 
  general_icu_diagnoses gid 
    ON gip.hadm_id = gid.hadm_id;