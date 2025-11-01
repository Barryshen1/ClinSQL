WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
),
mechanical_support_procedures AS (
  SELECT pe.subject_id, pe.itemid
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%IABP%' OR di.label LIKE '%Mechanical Circulatory Support%' 
  -- Add more conditions as necessary based on the specific itemids or labels for mechanical circulatory support
),
patient_procedure_counts AS (
  SELECT subject_id, COUNT(DISTINCT itemid) as num_procedures
  FROM mechanical_support_procedures
  WHERE subject_id IN (SELECT subject_id FROM female_patients)
  GROUP BY subject_id
)
SELECT MIN(num_procedures) as min_procedures
FROM patient_procedure_counts;