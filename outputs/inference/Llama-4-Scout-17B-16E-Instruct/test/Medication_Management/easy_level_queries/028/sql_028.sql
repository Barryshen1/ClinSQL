WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 44 AND 54 AND gender = 'F'
  ),
  
  -- Admissions for patients of interest
  admissions_of_interest AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_of_interest p ON a.subject_id = p.subject_id
  ),
  
  -- Prescriptions for antiplatelet therapy
  antiplatelet_prescriptions AS (
    SELECT p.hadm_id, p.subject_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.drug LIKE '%aspirin%' OR p.drug LIKE '%clopidogrel%' 
      OR p.drug LIKE '%prasugrel%' OR p.drug LIKE '%ticagrelor%' 
      OR p.drug LIKE '%cangrelor%' OR p.drug LIKE '%dipyridamole%'
  ),
  
  -- Calculate duration for each prescription
  prescription_durations AS (
    SELECT hadm_id, subject_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS prescription_duration
    FROM antiplatelet_prescriptions
    WHERE stoptime IS NOT NULL
  )

-- Calculate standard deviation of prescription durations
SELECT 
  STDDEV(prescription_duration) AS sd_prescription_duration
FROM prescription_durations
WHERE subject_id IN (
  SELECT subject_id
  FROM admissions_of_interest
);