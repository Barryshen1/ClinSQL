SELECT 
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0) AS average_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON a.hadm_id = diag.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE 
  p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
  AND diag.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%heart failure%'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;