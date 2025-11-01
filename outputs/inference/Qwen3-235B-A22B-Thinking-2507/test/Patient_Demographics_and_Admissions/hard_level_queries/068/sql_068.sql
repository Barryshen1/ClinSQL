SELECT COUNT(*) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  AND diag.seq_num = 1  -- Principal diagnosis
WHERE
  pat.gender = 'M'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'SKILLED NURSING FACILITY'
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '27651')  -- ICD-9 dehydration
    OR 
    (diag.icd_version = 10 AND diag.icd_code = 'E860')   -- ICD-10 dehydration
  )
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 43 AND 53;