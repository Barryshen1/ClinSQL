WITH 
  -- Filter patients and calculate first admission
  first_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 77 AND 87
      AND a.admittime = (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 WHERE a2.subject_id = a.subject_id)
  ),
  
  -- Calculate length of stay in days
  lengths_of_stay AS (
    SELECT 
      subject_id,
      hadm_id,
      DATE_DIFF(dischtime, admittime, 'DAY') AS length_of_stay_days
    FROM 
      first_admissions
  )

-- Calculate IQR of lengths of stay
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY length_of_stay_days) AS Q1,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY length_of_stay_days) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY length_of_stay_days) AS Q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY length_of_stay_days) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY length_of_stay_days) AS IQR
FROM 
  lengths_of_stay;