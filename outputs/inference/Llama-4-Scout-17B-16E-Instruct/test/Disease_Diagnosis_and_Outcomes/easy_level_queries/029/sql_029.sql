WITH 
  -- Define ICD codes for UGIB and COPD exacerbation
  icd_codes AS (
    SELECT '530.6' AS icd_code, 'Upper gastrointestinal bleeding' AS condition UNION ALL
    SELECT '491.21', 'COPD exacerbation' 
  ),
  
  -- Select relevant patients and admissions
  patients_admissions AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 69 AND 79
  ),
  
  -- Identify patients with UGIB and COPD exacerbation
  diagnoses AS (
    SELECT 
      subject_id,
      hadm_id,
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN (SELECT icd_code FROM icd_codes)
  ),
  
  -- Merge patients, admissions, and diagnoses
  final_data AS (
    SELECT 
      pa.subject_id,
      pa.hadm_id,
      pa.admittime,
      pa.dischtime,
      pa.hospital_expire_flag
    FROM 
      patients_admissions pa
    JOIN 
      diagnoses d
    ON 
      pa.hadm_id = d.hadm_id
      AND pa.subject_id = d.subject_id
  )

-- Calculate median hospital LOS
SELECT 
  APPROX_QUANTILES(
    CASE 
      WHEN dischtime IS NULL THEN NULL 
      ELSE TIMESTAMP_DIFF(COALESCE(dischtime, CURRENT_TIMESTAMP), admittime, DAY)
    END, 0.5) AS median_los
FROM 
  final_data
WHERE 
  hospital_expire_flag = 0;