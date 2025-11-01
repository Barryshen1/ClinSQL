SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND d.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND a.insurance = 'Medicare'
  AND a.admission_location IN ('EMERGENCY ROOM', 'EMERGENCY ROOM ADMIT')
  AND di.long_title LIKE '%pneumonia%';