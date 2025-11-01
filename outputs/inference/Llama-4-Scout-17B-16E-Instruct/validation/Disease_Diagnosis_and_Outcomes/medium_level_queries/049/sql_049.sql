WITH 
  -- Identify STEMI and NSTEMI patients
  myocardial_infarction AS (
    SELECT 
      di.subject_id,
      di.hadm_id,
      CASE 
        WHEN di.icd_code IN ('410.11', '410.21', '410.31', '410.41', '410.51', '410.61', '410.71', '410.81', '410.91') THEN 'STEMI'
        WHEN di.icd_code IN ('410.12', '410.22', '410.32', '410.42', '410.52', '410.62', '410.72', '410.82', '410.92') THEN 'NSTEMI'
        ELSE NULL
      END AS MI_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ),
  
  -- Patient demographics and admission details
  patient_details AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  ),
  
  -- Comorbidities
  comorbidities AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count,
      SUM(CASE WHEN icd_code LIKE '585%' OR icd_code LIKE '586%' THEN 1 ELSE 0 END) AS CKD,
      SUM(CASE WHEN icd_code LIKE '250%' THEN 1 ELSE 0 END) AS diabetes
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  )

SELECT 
  -- Patient demographics
  pd.gender,
  pd.anchor_age,
  mi.MI_type,
  
  -- LOS categories
  CASE 
    WHEN pd.LOS BETWEEN 1 AND 2 THEN '1-2 days'
    WHEN pd.LOS BETWEEN 3 AND 5 THEN '3-5 days'
    WHEN pd.LOS BETWEEN 6 AND 9 THEN '6-9 days'
    ELSE '>=10 days'
  END AS LOS_category,
  
  -- Comorbidity groups
  CASE 
    WHEN c.comorbidity_count BETWEEN 0 AND 1 THEN '0-1'
    WHEN c.comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_group,
  
  -- CKD and diabetes prevalence
  c.CKD,
  c.diabetes,
  
  -- In-hospital mortality
  pd.hospital_expire_flag
FROM 
  patient_details pd
JOIN 
  myocardial_infarction mi ON pd.subject_id = mi.subject_id AND pd.hadm_id = mi.hadm_id
JOIN 
  comorbidities c ON pd.subject_id = c.subject_id AND pd.hadm_id = c.hadm_id
WHERE 
  pd.gender = 'M'
  AND pd.anchor_age BETWEEN 51 AND 61
  AND mi.MI_type IN ('STEMI', 'NSTEMI')
ORDER BY 
  LOS_category, comorbidity_group;