SELECT COUNT(DISTINCT a.hadm_id) AS admission_count
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND a.admission_location = 'SKILLED NURSING FACILITY'
  AND a.insurance = 'Medicare'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '27651')
    OR
    (d.icd_version = 10 AND d.icd_code = 'E860')
  )
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53;