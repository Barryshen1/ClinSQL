SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
JOIN `physionet-data.mimiciv_3_1_hosp`.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses AS d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE pat.gender = 'F'
  AND adm.admission_location LIKE '%EMERGENCY%'
  AND adm.insurance = 'Medicare'
  AND adm.dischtime IS NOT NULL
  AND diag.seq_num = 1
  AND d_diag.long_title LIKE '%acute pancreatitis%'
  AND diag.icd_version = 10
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 72 AND 82;