WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 56 AND 66
),
-- Identify admissions with diabetes and heart failure
admissions_with_conditions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN patients_of_interest p ON a.subject_id = p.subject_id
  WHERE d.icd_code LIKE '%250%' OR d.icd_code LIKE '%428%'
),
-- Identify GLP-1 receptor agonist prescriptions
glp1_prescriptions AS (
  SELECT p.hadm_id, 
         CASE 
           WHEN p.drug LIKE '%exenatide%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%semaglutide%' 
           THEN TRUE ELSE FALSE 
         END AS is_glp1
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
),
-- Identify GLP-1 receptor agonist use in first 48 hours and last 24 hours
glp1_use AS (
  SELECT a.hadm_id,
         CASE 
           WHEN e.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) THEN 'first_48_hours'
           WHEN e.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR) AND a.dischtime THEN 'last_24_hours'
           ELSE NULL
         END AS period
  FROM admissions_with_conditions a
  JOIN glp1_prescriptions g ON a.hadm_id = g.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` e ON a.hadm_id = e.hadm_id
  WHERE g.is_glp1 = TRUE
)

-- Calculate prevalence
SELECT 
  period,
  COUNT(DISTINCT hadm_id) AS num_patients_with_glp1,
  (COUNT(DISTINCT hadm_id) * 1.0 / (SELECT COUNT(DISTINCT hadm_id) FROM admissions_with_conditions)) * 100 AS prevalence
FROM glp1_use
WHERE period IS NOT NULL
GROUP BY period;