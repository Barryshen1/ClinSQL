SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d 
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dd 
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE 
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_type = 'EMERGENCY'
  AND d.seq_num = 1
  AND dd.long_title LIKE '%acute pancreatitis%'
  AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 70 AND 80;