WITH 
  -- Define community-acquired pneumonia ICD codes
  cap_diagnoses AS (
    SELECT 
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
      long_title LIKE '%Pneumonia%' AND long_title LIKE '%Community-acquired%'
  ),
  
  -- Select relevant patient admissions
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
      p.gender = 'F'
      AND p.anchor_age BETWEEN 83 AND 93
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN (SELECT icd_code FROM cap_diagnoses)
          AND seq_num = 1  -- Primary diagnosis
      )
  )

-- Calculate hospital LOS and compute median
SELECT 
  APPROX_QUANTILES(DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), 'DAY'), 100)[OFFSET(50)] AS median_los
FROM 
  patient_admissions
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL;