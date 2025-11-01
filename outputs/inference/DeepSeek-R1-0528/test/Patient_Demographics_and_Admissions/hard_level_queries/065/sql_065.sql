SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
WHERE 
  pat.gender = 'M'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 72 AND 82
  AND adm.insurance = 'Medicare'
  AND adm.admission_location LIKE 'Transfer%Hospital%'
  AND adm.dischtime IS NOT NULL
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '4111') 
    OR 
    (diag.icd_version = 10 AND diag.icd_code = 'I20.0')
  );