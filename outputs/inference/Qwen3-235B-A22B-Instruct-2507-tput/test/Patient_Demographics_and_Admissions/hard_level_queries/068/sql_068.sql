SELECT COUNT(*) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND adm.insurance = 'Medicare'
  AND LOWER(adm.admission_location) LIKE '%skilled nursing%'
  AND diag.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%dehydration%'
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)
  ) BETWEEN 43 AND 53;