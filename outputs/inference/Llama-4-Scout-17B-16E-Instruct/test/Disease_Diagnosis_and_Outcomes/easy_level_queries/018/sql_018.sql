WITH 
  -- Calculate hospital length of stay
  hospital_stay AS (
    SELECT 
      a.subject_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_length_of_stay
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  ),
  
  -- Filter patients by age, gender, and primary diagnosis
  target_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      di.icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 45 AND 55
      AND di.seq_num = 1  -- Primary diagnosis
      AND di.icd_code LIKE '430%'  -- Hemorrhagic stroke ICD code
  )

SELECT 
  STDDEV(hospital_length_of_stay) AS sd_hospital_length_of_stay
FROM 
  hospital_stay
JOIN 
  target_patients tp ON hospital_stay.subject_id = tp.subject_id;