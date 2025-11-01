SELECT COUNT(DISTINCT a.hadm_id) AS completed_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
  ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY'
  AND a.dischtime IS NOT NULL
  AND d.seq_num = 1
  AND LOWER(d_icd.long_title) LIKE '%bowel obstruction%';