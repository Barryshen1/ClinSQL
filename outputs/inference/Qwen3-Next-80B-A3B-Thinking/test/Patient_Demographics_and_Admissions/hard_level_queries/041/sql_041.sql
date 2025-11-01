SELECT COUNT(*) AS count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
WHERE d.seq_num = 1
  AND di.long_title LIKE '%osteomyelitis%'
  AND a.admission_type = 'EMERGENCY'
  AND a.insurance = 'Medicare'
  AND p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90;