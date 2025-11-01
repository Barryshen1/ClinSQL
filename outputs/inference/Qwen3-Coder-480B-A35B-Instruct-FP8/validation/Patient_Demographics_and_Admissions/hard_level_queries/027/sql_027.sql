SELECT COUNT(DISTINCT a.hadm_id) AS index_admission_count
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND d.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
  AND a.admittime >= DATETIME(p.anchor_year, 1, 1, 0, 0, 0)
  AND (
    DATE_DIFF(DATE(a.admittime), DATE(DATETIME(p.anchor_year, 1, 1, 0, 0, 0)), YEAR) +
    p.anchor_age
  ) BETWEEN 70 AND 80;