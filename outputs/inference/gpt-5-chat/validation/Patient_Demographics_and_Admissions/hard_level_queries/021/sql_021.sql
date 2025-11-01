SELECT
  COUNT(DISTINCT adm.hadm_id) AS cohort_size
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 82 AND 92
  AND adm.insurance LIKE 'Medicare%'
  AND adm.admission_location LIKE 'Emergency%'
  AND adm.dischtime IS NOT NULL
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5770')
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
  )
;