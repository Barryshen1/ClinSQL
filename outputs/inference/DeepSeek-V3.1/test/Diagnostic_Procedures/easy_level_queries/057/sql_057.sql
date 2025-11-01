WITH catheterization_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 64 AND 74
    AND d.long_title LIKE '%diagnostic cardiac catheterization%'
  GROUP BY p.subject_id
)
SELECT 
  MIN(procedure_count) AS min_procedures_per_patient
FROM catheterization_procedures;