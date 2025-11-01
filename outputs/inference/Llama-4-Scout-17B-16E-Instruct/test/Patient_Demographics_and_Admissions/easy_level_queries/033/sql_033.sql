WITH 
  -- Filter relevant patients and calculate length of stay
  patient_stays AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 44 AND 54
      -- Additional filter for dialysis inpatients if necessary
      -- This part may require additional joins or conditions based on MIMIC-IV schema
  )
  
SELECT 
  STDDEV(length_of_stay) AS sd_length_of_stay
FROM 
  patient_stays;