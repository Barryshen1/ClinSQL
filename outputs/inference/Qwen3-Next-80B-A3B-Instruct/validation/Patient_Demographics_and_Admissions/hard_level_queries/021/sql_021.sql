SELECT COUNT(*) AS admission_count
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND p.anchor_age BETWEEN 82 AND 92
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.dischtime IS NOT NULL
  AND d.seq_num = 1  -- principal diagnosis
  AND (
    (d.icd_version = 9 AND d.icd_code = '577.0')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
  );