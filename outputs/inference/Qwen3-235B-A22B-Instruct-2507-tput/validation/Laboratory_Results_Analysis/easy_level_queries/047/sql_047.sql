SELECT MAX(l.valuenum) AS max_creatinine_24h
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l ON a.hadm_id = l.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d ON l.itemid = d.itemid
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag ON a.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND LOWER(d_diag.long_title) LIKE '%heart failure%'
  AND LOWER(d.label) = 'creatinine'
  AND LOWER(d.fluid) = 'blood'
  AND l.charttime >= a.admittime
  AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  AND l.valuenum IS NOT NULL;