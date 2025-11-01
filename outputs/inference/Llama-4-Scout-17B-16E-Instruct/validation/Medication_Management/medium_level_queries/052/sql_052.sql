WITH 
  patients_of_interest AS (
    SELECT 
      p.subject_id, 
      a.hadm_id, 
      ic.stay_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 45 AND 55
      AND a.admission_type = 'Elective'
      AND ic.los >= 48
  ),
  
  diabetes_heart_failure AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diag_icd`
    WHERE 
      icd_code IN ('250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13')  -- Type 2 Diabetes
      OR icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9')  -- Heart Failure
  ),
  
  first_48_hours AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      CASE 
        WHEN drug_type = 'Insulin' THEN 'Insulin'
        WHEN drug_type = 'Oral' THEN 'Oral'
        ELSE 'Other'
      END AS medication_type
    FROM 
      `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE 
      ie.starttime BETWEEN TIMESTAMP_ADD(icustay_intime, INTERVAL 0 HOUR) 
                         AND TIMESTAMP_ADD(icustay_intime, INTERVAL 48 HOUR)
  ),
  
  last_24_hours AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      CASE 
        WHEN drug_type = 'Insulin' THEN 'Insulin'
        WHEN drug_type = 'Oral' THEN 'Oral'
        ELSE 'Other'
      END AS medication_type
    FROM 
      `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE 
      ie.starttime BETWEEN TIMESTAMP_SUB(icustay_outtime, INTERVAL 24 HOUR) 
                         AND icustay_outtime
  )

-- Final query
SELECT 
  time_frame,
  medication_type,
  COUNT(*) AS count
FROM (
  SELECT 
    'First 48 hours' AS time_frame,
    medication_type
  FROM 
    patients_of_interest poi
  JOIN 
    diabetes_heart_failure dhf 
      ON poi.subject_id = dhf.subject_id AND poi.hadm_id = dhf.hadm_id
  JOIN 
    first_48_hours f48 
      ON poi.subject_id = f48.subject_id AND poi.hadm_id = f48.hadm_id AND poi.stay_id = f48.stay_id
  WHERE 
    f48.medication_type IN ('Insulin', 'Oral')

  UNION ALL

  SELECT 
    'Last 24 hours' AS time_frame,
    medication_type
  FROM 
    patients_of_interest poi
  JOIN 
    diabetes_heart_failure dhf 
      ON poi.subject_id = dhf.subject_id AND poi.hadm_id = dhf.hadm_id
  JOIN 
    last_24_hours l24 
      ON poi.subject_id = l24.subject_id AND poi.hadm_id = l24.hadm_id AND poi.stay_id = l24.stay_id
  WHERE 
    l24.medication_type IN ('Insulin', 'Oral')
) AS subquery
GROUP BY 
  time_frame, 
  medication_type
ORDER BY 
  time_frame, 
  medication_type;