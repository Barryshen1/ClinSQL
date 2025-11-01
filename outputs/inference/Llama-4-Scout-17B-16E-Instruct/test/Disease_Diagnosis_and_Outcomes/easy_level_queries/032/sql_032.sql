WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      EXTRACT(DAY FROM a.dischtime - a.admittime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 81 AND 91
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code = '584.9'
          AND seq_num = 1  -- Primary diagnosis
      )
  )
SELECT 
  QUANTILE(los, 0.75) - QUANTILE(los, 0.25) AS iqr_los
FROM 
  patients_of_interest;