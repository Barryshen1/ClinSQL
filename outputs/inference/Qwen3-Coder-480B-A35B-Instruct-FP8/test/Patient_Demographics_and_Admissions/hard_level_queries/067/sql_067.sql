SELECT COUNT(*) AS completed_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id AND di.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.hospital_expire_flag = 0
  AND d.long_title LIKE '%bowel obstruction%'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53;