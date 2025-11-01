WITH 
  -- Define common ACE inhibitors
  ace_inhibitors AS (
    SELECT 'Lisinopril' AS drug_name UNION ALL
    SELECT 'Enalapril' UNION ALL
    SELECT 'Captopril'  -- Add more as needed
  ),
  
  -- Filter relevant patients and prescriptions
  patient_prescriptions AS (
    SELECT p.subject_id, p.anchor_age, p.gender, 
           pr.hadm_id, pr.starttime, pr.stoptime, 
           pr.drug_type, pr.drug
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.subject_id = pr.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
  ),
  
  -- Filter ACE inhibitor prescriptions
  ace_prescriptions AS (
    SELECT subject_id, hadm_id, starttime, stoptime
    FROM patient_prescriptions
    WHERE LOWER(drug) IN (SELECT LOWER(drug_name) FROM ace_inhibitors)
  )

-- Calculate the longest prescription duration for each patient
SELECT subject_id, 
       MAX(DATE_DIFF(stoptime, starttime, DAY)) AS longest_duration_days
FROM ace_prescriptions
WHERE stoptime IS NOT NULL
GROUP BY subject_id
ORDER BY longest_duration_days DESC
LIMIT 1;