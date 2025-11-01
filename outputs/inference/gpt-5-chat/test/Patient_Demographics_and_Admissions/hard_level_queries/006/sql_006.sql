SELECT COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddiag
  ON diag.icd_code = ddiag.icd_code
  AND diag.icd_version = ddiag.icd_version
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 36 AND 46
  AND adm.insurance = 'Medicare'
  AND UPPER(adm.admission_location) = 'TRANSFER FROM OTHER HOSPITAL'
  AND diag.seq_num = 1
  AND LOWER(ddiag.long_title) LIKE '%hemorrh%'
  AND LOWER(ddiag.long_title) LIKE '%stroke%';