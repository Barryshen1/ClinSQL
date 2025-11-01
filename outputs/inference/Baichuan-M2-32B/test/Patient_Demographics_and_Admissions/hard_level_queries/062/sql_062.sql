SELECT COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d 
  ON a.hadm_id = d.hadm_id
WHERE 
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'Emergency Room'
  AND d.seq_num = 1
  AND d.icd_version = 10
  AND d.icd_code LIKE 'K31.0%'
  AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48;