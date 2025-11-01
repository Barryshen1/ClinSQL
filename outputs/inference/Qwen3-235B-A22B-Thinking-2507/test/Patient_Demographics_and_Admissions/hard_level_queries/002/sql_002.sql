SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  AND diag.seq_num = 1  -- Principal diagnosis only
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'M'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location IN (
    'EMERGENCY ROOM ADMIT',
    'TRANSFER FROM HOSPITAL EMERGENCY ROOM'
  )
  AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
  AND (
    pat.anchor_age - (pat.anchor_year - EXTRACT(YEAR FROM adm.admittime))
  ) BETWEEN 77 AND 87;