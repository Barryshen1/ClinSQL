SELECT STDDEV_SAMP(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND d.seq_num = 1
  AND (LOWER(did.long_title) LIKE '%sepsis%' OR LOWER(did.long_title) LIKE '%septic shock%')
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;