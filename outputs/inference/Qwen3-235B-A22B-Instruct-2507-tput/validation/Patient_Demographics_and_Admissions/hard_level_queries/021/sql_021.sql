SELECT COUNT(*) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
JOIN `physionet-data.mimiciv_3_1_hosp`.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 82 AND 92
  AND LOWER(adm.admission_location) LIKE '%emergency%'
  AND LOWER(adm.insurance) = 'medicare'
  AND adm.dischtime IS NOT NULL
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '577.0')
    OR
    (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
  );