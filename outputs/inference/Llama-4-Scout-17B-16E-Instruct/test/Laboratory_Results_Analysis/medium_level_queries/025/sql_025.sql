WITH 
  -- Filter patients based on age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 58 AND 68
  ),
  
  -- Filter admissions for chest pain or AMI
  target_admissions AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE admission_type IN ('Chest Pain', 'Acute Myocardial Infarction')
    AND subject_id IN (SELECT subject_id FROM target_patients)
  ),
  
  -- Filter lab events for Troponin T > 0.01 ng/mL
  troponin_t_events AS (
    SELECT l.value, l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
    WHERE d.label = 'Troponin T' 
    AND l.hadm_id IN (SELECT hadm_id FROM target_admissions)
    AND l.valuenum > 0.01
  )

-- Calculate Troponin T distribution
SELECT 
  AVG(valuenum) AS mean,
  STDDEV(valuenum) AS std_dev,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM troponin_t_events;