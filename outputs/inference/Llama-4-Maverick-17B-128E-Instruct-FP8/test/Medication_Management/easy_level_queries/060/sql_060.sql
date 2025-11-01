WITH relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 38 AND 48
),
ace_inhibitor_prescriptions AS (
  SELECT p.subject_id, p.starttime, p.stoptime, p.drug,
         DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN relevant_patients rp ON p.subject_id = rp.subject_id
  WHERE LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' 
     OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%ramipril%' 
     OR LOWER(p.drug) LIKE '%quinapril%' OR LOWER(p.drug) LIKE '%perindopril%' 
     OR LOWER(p.drug) LIKE '%trandolapril%' OR LOWER(p.drug) LIKE '%fosinopril%'
)
SELECT MAX(duration_days) AS longest_duration
FROM ace_inhibitor_prescriptions;