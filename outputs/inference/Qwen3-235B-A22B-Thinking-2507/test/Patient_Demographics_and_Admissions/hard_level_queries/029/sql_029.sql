SELECT COUNT(DISTINCT admissions.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON admissions.hadm_id = diag.hadm_id AND admissions.subject_id = diag.subject_id
WHERE
  patients.gender = 'F'
  AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 46 AND 56
  AND admissions.admission_type = 'TRANSFER'
  AND admissions.insurance = 'Medicare'
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 10 AND (diag.icd_code LIKE 'S720%' OR diag.icd_code LIKE 'S721%' OR diag.icd_code LIKE 'S722%'))
    OR
    (diag.icd_version = 9 AND diag.icd_code LIKE '820%')
  );