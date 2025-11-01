WITH 
  -- Define DKA/HHS ICD codes
  dka_hhs_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title IN ('Diabetic ketoacidosis', 'Hyperosmolar hyperglycemic state')
  ),
  
  -- Select target population
  target_population AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      DATE_DIFF(a.dischtime, a.admittime) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 73 AND 83
      AND d.seq_num = 1  -- Primary diagnosis
      AND d.icd_code IN (SELECT icd_code FROM dka_hhs_icd_codes)
  )

-- Calculate 25th percentile of hospital LOS
SELECT 
  APPROX_QUANTILES(los_days, 0.25)[OFFSET(1)] AS los_25th_percentile
FROM 
  target_population;