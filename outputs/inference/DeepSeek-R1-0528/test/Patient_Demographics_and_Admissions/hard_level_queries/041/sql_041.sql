SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
  AND diag.seq_num = 1  -- Principal diagnosis
WHERE
  adm.admission_location = 'EMERGENCY ROOM'
  AND adm.insurance = 'Medicare'
  AND p.gender = 'F'
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '730%')  -- ICD-9 osteomyelitis
    OR 
    (diag.icd_version = 10 AND diag.icd_code LIKE 'M86%')  -- ICD-10 osteomyelitis
  )
  AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 80 AND 90;