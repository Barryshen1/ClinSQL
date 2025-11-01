SELECT
  COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON diag.icd_code = icd.icd_code
  AND diag.icd_version = icd.icd_version
WHERE
  pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND diag.seq_num = 1  -- Principal diagnosis
  AND icd.long_title LIKE '%bowel obstruction%'
  AND EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age BETWEEN 43 AND 53;