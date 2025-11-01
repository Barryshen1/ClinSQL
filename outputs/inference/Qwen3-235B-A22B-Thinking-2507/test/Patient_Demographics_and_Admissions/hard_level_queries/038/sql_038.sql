SELECT COUNT(*) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
  -- Age 90-100 at admission (standard MIMIC calculation)
  pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 90 AND 100
  -- Male patients
  AND pat.gender = 'M'
  -- Medicare insurance (stored in uppercase)
  AND adm.insurance = 'MEDICARE'
  -- Transfer from another hospital (exact string match)
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  -- Principal diagnosis (seq_num=1) for ESRD
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5856')  -- ICD-9 585.6
    OR (diag.icd_version = 10 AND diag.icd_code = 'N186')  -- ICD-10 N18.6
  );