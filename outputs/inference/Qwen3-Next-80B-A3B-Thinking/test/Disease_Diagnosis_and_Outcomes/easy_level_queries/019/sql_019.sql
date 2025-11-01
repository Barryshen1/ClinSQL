SELECT STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS std_dev_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
  ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
WHERE d.seq_num = 1
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND (LOWER(d_icd.long_title) LIKE '%sepsis%' OR LOWER(d_icd.long_title) LIKE '%septic shock%');