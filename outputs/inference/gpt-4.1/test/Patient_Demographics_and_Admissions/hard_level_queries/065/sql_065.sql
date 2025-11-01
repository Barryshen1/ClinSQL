SELECT COUNT(*) AS total_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 72 AND 82
  AND adm.insurance LIKE '%Medicare%'
  AND adm.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '411.1')
    OR
    (diag.icd_version = 10 AND diag.icd_code = 'I20.0')
  )
  AND adm.dischtime IS NOT NULL;