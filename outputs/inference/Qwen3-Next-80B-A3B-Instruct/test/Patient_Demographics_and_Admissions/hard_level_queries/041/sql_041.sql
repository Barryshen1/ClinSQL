SELECT COUNT(DISTINCT a.hadm_id) AS index_admissions_count
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 80 AND 90
  AND a.admission_type = 'EMERGENCY'
  AND a.insurance = 'Medicare'
  AND d.seq_num = 1
  AND LOWER(dicd.long_title) LIKE '%osteomyelitis%';