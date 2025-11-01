WITH 
  -- Patient data with age and gender
  patient_data AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 43 AND 53
  ),
  
  -- Diagnosis data for heart failure and comorbidity count
  diagnosis_data AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),
  
  -- Heart failure diagnosis
  heart_failure AS (
    SELECT 
      subject_id,
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9', 
                    'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.5', 'I50.6', 'I50.7', 'I50.8', 'I50.9')
  ),
  
  -- ICU stay data
  icu_stay AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Combine data
  combined_data AS (
    SELECT 
      pd.subject_id,
      pd.hadm_id,
      pd.admittime,
      pd.dischtime,
      pd.deathtime,
      pd.hospital_expire_flag,
      dd.comorbidity_count,
      COALESCE(icu.los, 0) AS los  -- Use COALESCE to handle NULL los values
    FROM 
      patient_data pd
    JOIN 
      heart_failure hf
    ON 
      pd.subject_id = hf.subject_id AND pd.hadm_id = hf.hadm_id
    JOIN 
      diagnosis_data dd
    ON 
      pd.subject_id = dd.subject_id AND pd.hadm_id = dd.hadm_id
    LEFT JOIN 
      icu_stay icu
    ON 
      pd.subject_id = icu.subject_id AND pd.hadm_id = icu.hadm_id
  ),

  -- Categorize data
  categorized_data AS (
    SELECT 
      subject_id,
      hadm_id,
      hospital_expire_flag,
      deathtime,
      comorbidity_count,
      los,
      NTILE(4) OVER (ORDER BY los) AS los_quartile,
      CASE 
        WHEN comorbidity_count <= 5 THEN 'low'
        WHEN comorbidity_count BETWEEN 6 AND 10 THEN 'medium'
        ELSE 'high'
      END AS comorbidity_burden
    FROM 
      combined_data
  )

-- Calculate mortality by LOS quartiles and comorbidity burden
SELECT 
  los_quartile,
  comorbidity_burden,
  COUNT(CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 END) AS deaths,
  COUNT(*) AS total_patients,
  COUNT(CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 END) * 100.0 / COUNT(*) AS mortality_rate
FROM 
  categorized_data
GROUP BY 
  los_quartile,
  comorbidity_burden
ORDER BY 
  los_quartile, 
  comorbidity_burden;