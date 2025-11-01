SELECT
  COUNT(DISTINCT a.hadm_id) AS index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  p.anchor_age >= 80 AND p.anchor_age <= 90
  AND LOWER(p.gender) = 'f'
  AND UPPER(a.insurance) LIKE '%MEDICARE%'
  AND UPPER(a.admission_type) = 'EMERGENCY'
  AND di.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%osteomyelitis%';