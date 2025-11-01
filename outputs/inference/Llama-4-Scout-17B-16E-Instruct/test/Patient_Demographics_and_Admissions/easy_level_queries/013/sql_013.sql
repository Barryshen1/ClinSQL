WITH 
  -- Calculate hospital length of stay for each admission
  hospital_stays AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.gender,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  
  -- Calculate length of stay in days
  lengths_of_stay AS (
    SELECT 
      hadm_id,
      gender,
      anchor_age,
      (DATE(dischtime) - DATE(admittime)) AS length_of_stay_days
    FROM 
      hospital_stays
  )

-- Filter by age and gender, and find maximum length of stay
SELECT 
  MAX(length_of_stay_days) AS max_length_of_stay_days
FROM 
  lengths_of_stay
WHERE 
  gender = 'M' 
  AND anchor_age BETWEEN 58 AND 68;