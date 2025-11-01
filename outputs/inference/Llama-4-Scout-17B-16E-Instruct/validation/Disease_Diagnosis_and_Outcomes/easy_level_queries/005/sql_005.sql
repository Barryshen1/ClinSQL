WITH 
  -- Identify ischemic stroke admissions
  ischemic_stroke_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
      a.admission_type = 'emergency'  
      AND d.icd_code IN ('433.0', '433.1', '433.2', '433.3', '433.4', '433.5', '433.6', '433.7', '433.8', '433.9')  
      AND d.seq_num = 1  
  ),
  -- Filter by age and gender
  target_patients AS (
    SELECT 
      isa.hadm_id,
      isa.admittime,
      isa.dischtime
    FROM 
      ischemic_stroke_admissions isa
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON isa.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
  )

-- Calculate median hospital LOS
SELECT 
  APPROX_QUANTILES(DATE_DIFF(dischtime, admittime, DAY), 0.5) AS median_los_days
FROM 
  target_patients;