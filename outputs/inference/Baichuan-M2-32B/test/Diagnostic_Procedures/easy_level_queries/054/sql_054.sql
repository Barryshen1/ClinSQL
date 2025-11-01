WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
),
patient_procedures AS (
  SELECT 
    e.subject_id,
    pr.icd_code
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
    ON e.subject_id = pr.subject_id AND e.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE d.long_title LIKE '%echocardiography%'
),
patient_procedure_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedures
  FROM patient_procedures
  GROUP BY subject_id
),
eligible_patients AS (
  SELECT DISTINCT subject_id 
  FROM eligible_admissions
)
SELECT 
  MAX(IF(ppc.distinct_procedures IS NULL, 0, ppc.distinct_procedures)) AS max_distinct_procedures
FROM eligible_patients ep
LEFT JOIN patient_procedure_counts ppc 
  ON ep.subject_id = ppc.subject_id;