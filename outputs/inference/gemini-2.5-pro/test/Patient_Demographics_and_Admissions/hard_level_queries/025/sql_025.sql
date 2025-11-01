SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  -- Patient criteria
  pat.gender = 'F'
  AND (
    CAST(EXTRACT(YEAR FROM adm.admittime) AS INT64) - pat.anchor_year + pat.anchor_age
  ) BETWEEN 65 AND 75
  AND adm.insurance = 'Medicare'
  -- Admission criteria
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  -- Diagnosis criteria
  AND diag.seq_num = 1
  AND LOWER(d_diag.long_title) LIKE '%heart failure%';