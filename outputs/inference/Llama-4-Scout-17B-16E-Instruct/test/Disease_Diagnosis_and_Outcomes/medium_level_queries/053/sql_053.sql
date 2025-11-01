WITH 
-- Patient demographics and admission details
patient_adm AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
),

-- Identify pneumonia admissions and type
pneumonia_adm AS (
  SELECT 
    pa.hadm_id,
    pa.subject_id,
    CASE 
      WHEN di.icd_code IN ('507.0', '507.1', '507.8', '507.9') THEN 'aspiration'
      ELSE 'community-acquired'
    END AS pneumonia_type,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag
  FROM 
    patient_adm pa
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON pa.hadm_id = di.hadm_id
  WHERE 
    pa.anchor_age BETWEEN 39 AND 49
    AND pa.gender = 'M'
    AND di.icd_code IN ('481', '482', '483', '484', '485', '486', '507.0', '507.1', '507.8', '507.9')
),

-- ICU stay details
icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    first_careunit
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Comorbidity count
comorbidity_count AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    subject_id
)

-- Final calculation
SELECT 
  pa.pneumonia_type,
  CASE 
    WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
    WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  COALESCE(ic.stay_id IS NOT NULL, FALSE) AS day1_icu,
  AVG(CASE WHEN pa.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate,
  AVG(cc.comorbidity_count) AS avg_comorbidity_count
FROM 
  pneumonia_adm pa
  LEFT JOIN icu_stay ic ON pa.hadm_id = ic.hadm_id AND TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY) > ic.intime
  LEFT JOIN comorbidity_count cc ON pa.subject_id = cc.subject_id
GROUP BY 
  pa.pneumonia_type,
  CASE 
    WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
    WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END,
  COALESCE(ic.stay_id IS NOT NULL, FALSE)
ORDER BY 
  pa.pneumonia_type,
  los_category,
  day1_icu;