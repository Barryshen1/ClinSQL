WITH 
-- Define a list of common antiplatelet drugs used in DAPT
antiplatelet_drugs AS (
  SELECT DISTINCT 'aspirin' AS drug_name UNION
  SELECT 'clopidogrel' UNION
  SELECT 'prasugrel' UNION
  SELECT 'ticagrelor' UNION
  SELECT 'aspirin/dipyridamole' 
),

-- Select relevant patient and prescription data
patient_prescriptions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'M' AND
    p.anchor_age BETWEEN 57 AND 67 AND
    LOWER(pr.drug) IN (SELECT LOWER(drug_name) FROM antiplatelet_drugs)
),

-- Calculate prescription durations
prescription_durations AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    DATETIME_DIFF(stoptime, starttime, HOUR) AS duration_hours
  FROM 
    patient_prescriptions
  WHERE 
    stoptime IS NOT NULL
)

-- Calculate IQR of prescription durations
SELECT 
  APPROX_QUANTILES(duration_hours, 0.25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_hours, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(duration_hours, 0.75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(duration_hours, 0.75)[OFFSET(0)] - APPROX_QUANTILES(duration_hours, 0.25)[OFFSET(0)] AS IQR
FROM 
  prescription_durations;