SELECT PERCENTILE_CONT(ARRAY_AGG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)), 0.5) AS median_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
  ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND d.seq_num = 1
  AND d.icd_code LIKE 'I63%';