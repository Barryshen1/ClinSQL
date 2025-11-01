SELECT COUNT(*) AS admission_count
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 79 AND 89
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY'
  AND d.seq_num = 1
  AND LOWER(did.long_title) LIKE '%pneumonia%';