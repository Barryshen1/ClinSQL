SELECT COUNT(*) AS index_admissions_count
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
  ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
WHERE p.gender = 'F'
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 65 AND 75
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSPITAL'
  AND d.seq_num = 1
  AND LOWER(d_icd.long_title) LIKE '%heart failure%';