SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
WHERE 
  pat.gender = 'F'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 85 AND 95
  AND adm.insurance = 'Medicare'
  AND adm.admission_type = 'TRANSFER FROM HOSPITAL'
  AND diag.seq_num = 1  -- Principal diagnosis
  AND LOWER(icd.long_title) LIKE '%osteomyelitis%';