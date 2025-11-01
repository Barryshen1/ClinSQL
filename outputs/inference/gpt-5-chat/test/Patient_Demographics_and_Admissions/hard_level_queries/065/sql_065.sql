SELECT
  COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
  ON diag.icd_code = ddiag.icd_code
  AND diag.icd_version = ddiag.icd_version
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 72 AND 82
  AND LOWER(adm.insurance) = 'medicare'
  AND LOWER(adm.admission_location) LIKE '%hospital%'
  AND diag.seq_num = 1
  AND LOWER(ddiag.long_title) LIKE '%unstable angina%'
  AND adm.dischtime IS NOT NULL;