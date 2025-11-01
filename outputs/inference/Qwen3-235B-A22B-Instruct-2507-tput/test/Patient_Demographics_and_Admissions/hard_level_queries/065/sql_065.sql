SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON a.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 72 AND 82
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%hospital%'
  AND a.dischtime IS NOT NULL
  AND diag.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%unstable angina%';