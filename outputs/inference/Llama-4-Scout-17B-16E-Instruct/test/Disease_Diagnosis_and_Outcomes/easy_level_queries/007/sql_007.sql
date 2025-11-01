WITH 
  admissions AS (
    SELECT 
      subject_id, 
      hadm_id, 
      admittime, 
      dischtime, 
      deathtime, 
      admission_type, 
      admit_provider_id, 
      admission_location, 
      discharge_location, 
      insurance, 
      language, 
      marital_status, 
      race, 
      edregtime, 
      edouttime, 
      hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  
  patients AS (
    SELECT 
      subject_id, 
      gender, 
      anchor_age, 
      anchor_year, 
      anchor_year_group, 
      dod
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients`
  ),
  
  los_data AS (
    SELECT 
      a.hadm_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      admissions a
    INNER JOIN 
      patients p ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 84 AND 94
      AND a.admission_type = 'elective'
      AND LOWER(a.discharge_location) LIKE '%ugib%'
  )

SELECT 
  PERCENTILE_CONT(los, 0.75) - PERCENTILE_CONT(los, 0.25) OVER () AS iqr_los
FROM 
  los_data;