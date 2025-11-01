SELECT 
  COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 38 AND 48
  AND adm.insurance = 'Medicare'
  AND adm.admission_location LIKE 'EMER%' -- from ED
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5750') -- ICD-9 acute cholecystitis
    OR (diag.icd_version = 10 AND diag.icd_code = 'K810') -- ICD-10 acute cholecystitis
  );