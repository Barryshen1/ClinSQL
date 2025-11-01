SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  AND diag.seq_num = 1
WHERE
  pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 63 AND 73
  AND (
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I48%')
    OR 
    (diag.icd_version = 9 AND diag.icd_code LIKE '427.3%')
  );