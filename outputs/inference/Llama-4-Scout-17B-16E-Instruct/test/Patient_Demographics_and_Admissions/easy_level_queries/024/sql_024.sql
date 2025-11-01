WITH 
  first_admissions AS (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      hospital_expire_flag,  
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  
  -- Identify CABG procedure
  cabg_procedures AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_code LIKE '36.0%'  
  ),
  
  -- Select target population on first admission
  target_population AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.hospital_expire_flag,
      p.anchor_age,
      p.gender
    FROM 
      first_admissions a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      cabg_procedures c
    ON 
      a.hadm_id = c.hadm_id
    WHERE 
      a.rn = 1
      AND p.gender = 'F'
      AND p.anchor_age BETWEEN 35 AND 45
  )

-- Calculate in-hospital mortality
SELECT 
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 1.0 / COUNT(hadm_id) AS mortality_rate,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS num_deaths,
  COUNT(hadm_id) AS total_patients
FROM 
  target_population;