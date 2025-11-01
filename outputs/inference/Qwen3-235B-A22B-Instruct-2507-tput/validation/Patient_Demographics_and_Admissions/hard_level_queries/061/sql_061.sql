SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND LOWER(adm.admission_location) LIKE '%hospital%' 
  AND diag.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%atrial fibrillation%'
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 63 AND 73;