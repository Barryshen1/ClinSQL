SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.insurance = 'Medicare'
  AND di.seq_num = 1
  AND LOWER(dicd.long_title) LIKE '%obstruction%'
  AND a.hospital_expire_flag = 0;