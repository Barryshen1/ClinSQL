WITH 
  -- Define dehydration ICD codes
  dehydration_icd AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Dehydration%'
  ),
  
  -- Identify relevant admissions
  eligible_admissions AS (
    SELECT 
      a.hadm_id,
      a.admission_location,
      a.insurance,
      p.anchor_age,
      p.gender,
      p.subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 43 AND 53
      AND a.admission_location = 'SNF'
      AND a.insurance = 'Medicare'
  ),
  
  -- Identify admissions with principal diagnosis of dehydration
  dehydration_admissions AS (
    SELECT 
      di.hadm_id,
      di.icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      dehydration_icd d
    ON 
      di.icd_code = d.icd_code
    WHERE 
      di.seq_num = 1  -- Principal diagnosis
  )

-- Count eligible admissions
SELECT 
  COUNT(DISTINCT ea.hadm_id) AS num_admissions
FROM 
  eligible_admissions ea
JOIN 
  dehydration_admissions da
ON 
  ea.hadm_id = da.hadm_id;