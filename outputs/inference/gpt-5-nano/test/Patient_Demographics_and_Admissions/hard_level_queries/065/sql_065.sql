SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
  AND di.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
  ON di.icd_code = dicd.icd_code
  AND di.icd_version = dicd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 72 AND 82
  AND UPPER(a.insurance) = 'MEDICARE'
  AND a.admission_type = 'TRANSFER'
  AND a.dischtime IS NOT NULL
  AND LOWER(dicd.long_title) LIKE '%unstable angina%';