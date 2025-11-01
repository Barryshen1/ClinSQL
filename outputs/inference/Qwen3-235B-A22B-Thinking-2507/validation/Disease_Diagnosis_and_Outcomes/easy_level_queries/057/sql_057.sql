SELECT 
  MIN(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0) AS min_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
WHERE 
  pat.gender = 'F'
  AND diag.seq_num = 1
  AND diag.icd_version = 10
  AND diag.icd_code >= 'J12'
  AND diag.icd_code < 'J19'
  AND adm.dischtime IS NOT NULL
  AND adm.admittime IS NOT NULL
  AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 88 AND 98;