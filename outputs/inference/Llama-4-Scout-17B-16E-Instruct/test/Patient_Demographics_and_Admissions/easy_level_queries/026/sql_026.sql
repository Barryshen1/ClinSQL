WITH 
  -- Filter patients by age and gender
  eligible_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      p.dod
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.anchor_age BETWEEN 48 AND 58
      AND p.gender = 'M'
  ),
  
  -- Filter admissions and procedures for CABG
  cabg_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` icd ON a.hadm_id = icd.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` ip ON icd.icd_code = ip.icd_code AND icd.icd_version = ip.icd_version
    WHERE 
      ip.long_title LIKE '%CABG%'
      AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
      AND a.admission_type = 'Elective'  # Assuming first admission is elective
  ),
  
  -- Determine in-hospital mortality
  mortality_outcomes AS (
    SELECT 
      subject_id,
      hadm_id,
      CASE 
        WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS in_hospital_death
    FROM 
      cabg_admissions
  )

-- Calculate 25th percentile of in-hospital mortality
SELECT 
  APPROX_QUANTILES(in_hospital_death, 100)[OFFSET(25)] AS percentile_25_mortality
FROM 
  mortality_outcomes;