SELECT COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND d.seq_num = 1
  AND dicd.long_title LIKE '%acute cholecystitis%'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48;