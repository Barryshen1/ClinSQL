SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE 
  pat.gender = 'F'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND adm.dischtime IS NOT NULL
  AND diag.seq_num = 1  -- Principal diagnosis
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5770') 
    OR 
    (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
  )
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) 
    BETWEEN 82 AND 92
  );