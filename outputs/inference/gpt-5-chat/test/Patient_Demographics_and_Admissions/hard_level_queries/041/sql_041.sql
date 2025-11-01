SELECT 
  COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pat.subject_id = adm.subject_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE 
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 80 AND 90
  AND adm.insurance = 'Medicare'
  AND adm.admission_location LIKE 'EMERGENCY%'
  AND dx.seq_num = 1
  AND (
    (dx.icd_version = 9 AND dx.icd_code LIKE '730%')  -- Osteomyelitis ICD-9
    OR
    (dx.icd_version = 10 AND dx.icd_code LIKE 'M86%') -- Osteomyelitis ICD-10
  );