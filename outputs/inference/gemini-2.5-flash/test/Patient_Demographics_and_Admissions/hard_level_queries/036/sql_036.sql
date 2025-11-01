SELECT
  COUNT(DISTINCT adm.hadm_id)
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'F' -- Female patients
  AND adm.insurance = 'Medicare' -- Medicare patients
  AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 72 AND 82 -- Age at admission 72-82
  AND adm.admission_type = 'EMERGENCY' -- Admitted via Emergency Department
  AND adm.hospital_expire_flag = 0 -- Discharged alive (not expired in hospital)
  AND diag.seq_num = 1 -- Principal diagnosis
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '5770%') -- ICD-9 for Acute Pancreatitis (e.g., 577.0)
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%') -- ICD-10 for Acute Pancreatitis (e.g., K85.0, K85.1)
  );