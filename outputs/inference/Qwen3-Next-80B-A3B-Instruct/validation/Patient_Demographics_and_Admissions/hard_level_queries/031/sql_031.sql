SELECT COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '780.2')
    OR
    (d.icd_version = 10 AND d.icd_code = 'R55')
  )
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 62 AND 72;