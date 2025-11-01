SELECT
  COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
  ON dx.icd_code = icd.icd_code
  AND dx.icd_version = icd.icd_version
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND adm.insurance = 'Medicare'
  AND UPPER(adm.admission_location) LIKE '%EMERGENCY ROOM%'
  AND dx.seq_num = 1
  AND LOWER(icd.long_title) LIKE '%pneumonia%'
;