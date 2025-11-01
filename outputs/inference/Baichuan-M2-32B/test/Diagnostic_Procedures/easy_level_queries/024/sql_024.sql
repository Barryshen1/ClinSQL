WITH angiography_pci_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 9
    AND (long_title LIKE '%coronary angiography%' 
         OR long_title LIKE '%percutaneous coronary intervention%'
         OR long_title LIKE '%pci%')
),
eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 58 AND 68
),
admission_procedures AS (
  SELECT 
    e.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_procedure_count
  FROM eligible_admissions e
  LEFT JOIN (
    SELECT pi.hadm_id, pi.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN angiography_pci_codes ac 
      ON pi.icd_code = ac.icd_code
      AND pi.icd_version = ac.icd_version  -- Ensures matching version 9
  ) pi ON e.hadm_id = pi.hadm_id
  GROUP BY e.hadm_id
)
SELECT 
  APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(75)] AS p75
FROM admission_procedures;