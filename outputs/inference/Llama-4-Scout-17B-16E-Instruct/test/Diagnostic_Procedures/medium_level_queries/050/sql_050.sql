WITH 
  -- Filter patients and admissions
  patient_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 90 AND 100
  ),
  
  -- Filter TIA admissions
  tia_admissions AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '433%'  -- TIA ICD code
  ),
  
  -- Filter diagnostic imaging procedures
  diagnostic_procedures AS (
    SELECT 
      p.hadm_id,
      COUNT(*) as num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON 
      p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
    WHERE 
      d.long_title LIKE '%imaging%'  -- Diagnostic imaging
    GROUP BY 
      p.hadm_id
  ),
  
  -- Calculate stay length and categorize
  categorized_stays AS (
    SELECT 
      pa.hadm_id,
      pa.admittime,
      pa.dischtime,
      TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) as stay_length
    FROM 
      patient_admissions pa
    WHERE 
      pa.hadm_id IN (SELECT hadm_id FROM tia_admissions)
  ),
  
  -- Join procedures with categorized stays
  final_data AS (
    SELECT 
      cs.hadm_id,
      cs.stay_length,
      COALESCE(dp.num_procedures, 0) as num_procedures
    FROM 
      categorized_stays cs
    LEFT JOIN 
      diagnostic_procedures dp
    ON 
      cs.hadm_id = dp.hadm_id
  )

-- Calculate mean, min, max procedures per admission for each stay length category
SELECT 
  CASE 
    WHEN stay_length BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN stay_length BETWEEN 4 AND 7 THEN '4-7 days'
  END as stay_category,
  AVG(num_procedures) as mean_procedures,
  MIN(num_procedures) as min_procedures,
  MAX(num_procedures) as max_procedures
FROM 
  final_data
GROUP BY 
  CASE 
    WHEN stay_length BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN stay_length BETWEEN 4 AND 7 THEN '4-7 days'
  END;