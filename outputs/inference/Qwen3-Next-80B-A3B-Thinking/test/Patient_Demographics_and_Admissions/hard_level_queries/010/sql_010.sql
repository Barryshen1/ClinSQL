SELECT COUNT(DISTINCT a.hadm_id) AS count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
  ON a.hadm_id = d_icd.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON d_icd.icd_code = d_diag.icd_code
  AND d_icd.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND p.anchor_age BETWEEN 43 AND 53
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND d_icd.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%diabetic ketoacidosis%';