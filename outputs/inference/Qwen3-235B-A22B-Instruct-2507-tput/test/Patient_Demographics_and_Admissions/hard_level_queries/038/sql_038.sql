SELECT COUNT(*) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
JOIN `physionet-data.mimiciv_3_1_hosp`.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  -- Male patients
  pat.gender = 'M'
  -- Age at admission between 90 and 100
  AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 90 AND 100
  -- Medicare insurance
  AND LOWER(adm.insurance) = 'medicare'
  -- Admission location: transfer from another hospital
  AND LOWER(adm.admission_location) LIKE '%transfer%hospital%'
  -- Principal diagnosis (seq_num = 1)
  AND diag.seq_num = 1
  -- ICD-9 585.6 or ICD-10 N18.6 for end-stage renal disease
  AND (
    (diag.icd_code = '585.6' AND diag.icd_version = 9)
    OR (diag.icd_code = 'N18.6' AND diag.icd_version = 10)
  );