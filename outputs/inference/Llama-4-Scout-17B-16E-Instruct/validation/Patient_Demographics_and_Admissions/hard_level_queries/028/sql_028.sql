WITH 
  -- ... (rest of the CTEs remain the same)

  admissions_criteria AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.admission_type,
      a.admit_provider_id,
      a.admission_location,
      p.gender,
      p.anchor_age,
      a.insurance,
      a.hospital_expire_flag,
      d_icd_diagnoses.long_title AS diagnosis,
      DATE_DIFF(a.dischtime, a.admittime) AS index_los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd 
        ON a.hadm_id = icd.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd_diagnoses 
        ON icd.icd_code = d_icd_diagnoses.icd_code AND icd.icd_version = d_icd_diagnoses.icd_version
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 55 AND 65
      AND a.admission_type = 'Emergency'
      AND d_icd_diagnoses.long_title LIKE '%Cellulitis%'
      AND a.insurance = 'Medicare'
  ),
  
  -- ... (rest of the CTEs remain the same);