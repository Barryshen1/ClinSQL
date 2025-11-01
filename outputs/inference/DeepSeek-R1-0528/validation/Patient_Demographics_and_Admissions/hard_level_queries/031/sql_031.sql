SELECT COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  adm.admission_location = 'EMERGENCY ROOM'  -- ED admissions
  AND adm.insurance = 'Medicare'             -- Medicare patients
  AND pat.gender = 'F'                       -- Female
  AND diag.seq_num = 1                       -- Principal diagnosis
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '7802')  -- ICD-9 syncope
    OR 
    (diag.icd_version = 10 AND diag.icd_code = 'R55')  -- ICD-10 syncope
  )
  AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age)
      BETWEEN 62 AND 72;  -- Age 62-72 at admission;