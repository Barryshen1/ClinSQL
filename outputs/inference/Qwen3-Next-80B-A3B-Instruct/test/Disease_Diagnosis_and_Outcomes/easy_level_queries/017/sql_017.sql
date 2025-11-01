SELECT MAX(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
  ON p.subject_id = adm.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 84 AND 94
  AND diag.seq_num = 1
  AND (
    LOWER(d_diag.long_title) LIKE '%ischemic stroke%'
    OR LOWER(d_diag.long_title) LIKE '%cerebral infarction%'
    OR d_diag.icd_code IN (
      '433.01', '433.11', '433.21', '433.31', '433.81', '433.91',
      '434.00', '434.01', '434.10', '434.11', '434.90', '434.91', '436',
      'I63.0', 'I63.1', 'I63.2', 'I63.3', 'I63.4', 'I63.5', 'I63.6', 'I63.7', 'I63.8', 'I63.9'
    )
  );