WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 76 AND 86
  AND a.admission_type = 'Elective'  -- Assuming first admission is elective, adjust as needed
),

-- Identify ICU stays for these patients
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_of_interest p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),

-- Identify patients on DAPT
dapt_patients AS (
  SELECT DISTINCT p.subject_id
  FROM patients_of_interest p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.hadm_id = pr.hadm_id
  WHERE pr.drug LIKE '%aspirin%' 
  AND (pr.drug LIKE '%clopidogrel%' OR pr.drug LIKE '%prasugrel%' OR pr.drug LIKE '%ticagrelor%')
)

-- Calculate average ICU LOS for DAPT patients
SELECT 
  AVG(DATE_DIFF(i.outtime, i.intime, DAY)) AS avg_icu_los
FROM 
icu_stays i
JOIN dapt_patients d ON i.subject_id = d.subject_id;