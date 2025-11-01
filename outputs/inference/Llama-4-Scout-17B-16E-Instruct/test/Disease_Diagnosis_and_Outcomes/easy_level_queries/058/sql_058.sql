WITH 
  -- Filter admissions for females aged 37-47 with primary hemorrhagic stroke
  target_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      DATE_DIFF(a.dischtime, a.admittime, 'DAY') AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 37 AND 47
      AND d.icd_code LIKE '430%'  -- ICD code for hemorrhagic stroke
      AND d.seq_num = 1  -- Primary diagnosis
  )

-- Calculate 75th percentile of LOS
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los
FROM 
  target_admissions;