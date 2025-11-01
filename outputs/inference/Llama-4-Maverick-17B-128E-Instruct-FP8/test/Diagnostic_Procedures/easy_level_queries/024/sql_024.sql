WITH patient_procedures AS (
  SELECT DISTINCT p.subject_id, pr.hadm_id, pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON p.subject_id = pr.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68
  AND ((pr.icd_version = 9 AND pr.icd_code BETWEEN '00.66' AND '00.68') 
       OR (pr.icd_version = 10 AND pr.icd_code LIKE '02%'))
),
procedure_counts AS (
  SELECT subject_id, hadm_id, COUNT(DISTINCT icd_code) as num_procedures
  FROM patient_procedures
  GROUP BY subject_id, hadm_id
)

SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th
FROM procedure_counts;