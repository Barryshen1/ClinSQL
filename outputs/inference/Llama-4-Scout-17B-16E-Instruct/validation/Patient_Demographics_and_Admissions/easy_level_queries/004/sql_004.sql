WITH 
  -- Filter patients who are female and between 70 and 80 years old
  filtered_patients AS (
    SELECT subject_id, anchor_age, gender, dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 70 AND 80
  ),
  
  -- Filter first admissions for these patients
  first_admissions AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN filtered_patients p ON a.subject_id = p.subject_id
    WHERE a.admission_type = 'New'  -- Assuming 'New' indicates a first admission
  ),

  -- Calculate length of stay for each admission
  lengths_of_stay AS (
    SELECT hadm_id, 
           TIMESTAMP_DIFF(COALESCE(dischtime, admittime), admittime, DAY) AS los_days
    FROM first_admissions
  )

-- Calculate the standard deviation of length of stay
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM lengths_of_stay;