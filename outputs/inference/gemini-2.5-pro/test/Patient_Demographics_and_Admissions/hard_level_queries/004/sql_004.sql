SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
  ON dx.icd_code = d_dx.icd_code
  AND dx.icd_version = d_dx.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 85 AND 95
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  AND dx.seq_num = 1
  AND LOWER(d_dx.long_title) LIKE '%osteomyelitis%';