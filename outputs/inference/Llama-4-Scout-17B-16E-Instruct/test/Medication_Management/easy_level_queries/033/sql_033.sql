WITH 
-- Identify ARB drugs
arb_drugs AS (
  SELECT DISTINCT drug 
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%angiotensin%' AND LOWER(drug) LIKE '%receptor%' AND LOWER(drug) LIKE '%blocker%'
),

-- Filter patients and prescriptions
patient_prescriptions AS (
  SELECT p.subject_id, p.anchor_age, p.gender, 
         pr.hadm_id, pr.starttime, pr.stoptime, pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
  ON p.subject_id = pr.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 77 AND 87
    AND pr.drug IN (SELECT drug FROM arb_drugs)
    AND pr.stoptime IS NOT NULL  -- Ensure we have a valid duration
)

-- Calculate average duration
SELECT 
  AVG(DATE_DIFF(stoptime, starttime, DAY)) AS average_duration_days
FROM patient_prescriptions;