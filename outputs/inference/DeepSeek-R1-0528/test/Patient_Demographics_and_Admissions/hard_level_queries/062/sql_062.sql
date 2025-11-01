SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
  ON diag.icd_code = icd.icd_code
  AND diag.icd_version = icd.icd_version
WHERE pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND diag.seq_num = 1  -- Principal diagnosis
  AND icd.long_title = 'Acute cholecystitis'  -- Validates code mapping
  AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 38 AND 48;