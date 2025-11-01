SELECT
  COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.hadm_id = di.hadm_id
  AND di.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND a.insurance = 'MEDICARE'
  AND a.admission_location = 'EMERGENCY DEPARTMENT'
  AND LOWER(dd.long_title) LIKE '%pneumonia%'
;