SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code
  AND d.icd_version = diag.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM ANOTHER HEALTH CARE FACILITY'
  AND d.seq_num = 1
  AND LOWER(diag.long_title) LIKE '%atrial fibrillation%';