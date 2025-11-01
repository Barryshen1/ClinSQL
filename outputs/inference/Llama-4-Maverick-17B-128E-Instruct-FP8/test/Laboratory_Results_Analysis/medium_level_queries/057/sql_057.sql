WITH acs_diagnoses AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE (icd_version = 10 AND lower(long_title) LIKE '%acute coronary syndrome%') 
  OR (icd_version = 9 AND lower(long_title) LIKE '%acute coronary syndrome%')
),
acs_admissions AS (
  SELECT DISTINCT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE icd_code IN (SELECT icd_code FROM acs_diagnoses)
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p 
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id 
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89 
  AND a.hadm_id IN (SELECT hadm_id FROM acs_admissions)
),
troponin_t_measurements AS (
  SELECT e.hadm_id, e.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY e.hadm_id ORDER BY e.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` e 
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` i ON e.itemid = i.itemid 
  WHERE lower(i.label) LIKE '%troponin t%' AND e.valuenum IS NOT NULL AND e.hadm_id IN (SELECT hadm_id FROM eligible_patients)
),
categorized_troponin AS (
  SELECT hadm_id, 
         CASE 
           WHEN valuenum <= 0.04 THEN 'Normal'
           WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline'
           ELSE 'Elevated'
         END AS category
  FROM troponin_t_measurements 
  WHERE rn = 1
)
SELECT category, COUNT(*) as admission_count
FROM categorized_troponin
GROUP BY category;