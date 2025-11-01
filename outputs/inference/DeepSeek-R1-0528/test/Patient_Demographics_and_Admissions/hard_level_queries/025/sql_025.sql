SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  AND adm.subject_id = diag.subject_id
WHERE 
  pat.gender = 'F'  -- Female patients
  AND adm.insurance = 'Medicare'  -- Medicare insurance
  AND adm.admission_type = 'TRANSFER'  -- Transferred from another hospital
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 65 AND 75  -- Age 65-75 at admission
  AND diag.seq_num = 1  -- Principal diagnosis
  AND (  -- Heart failure ICD codes
    (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
    OR 
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
  );