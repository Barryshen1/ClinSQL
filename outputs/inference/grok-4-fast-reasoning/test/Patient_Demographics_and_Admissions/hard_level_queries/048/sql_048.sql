SELECT COUNT(DISTINCT a.hadm_id) AS cohort_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND p.anchor_age BETWEEN 79 AND 89
  AND d.seq_num = 1
  AND LOWER(icd.long_title) LIKE '%pneumonia%';