SELECT MAX(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND d.seq_num = 1
  AND LOWER(di.long_title) LIKE '%sepsis%'
  AND (LOWER(di.long_title) LIKE '%septic shock%' OR LOWER(di.long_title) LIKE '%sepsis%');