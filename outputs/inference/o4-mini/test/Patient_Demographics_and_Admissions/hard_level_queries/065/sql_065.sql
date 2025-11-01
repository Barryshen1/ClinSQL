SELECT
  COUNT(*) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  USING (subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON a.subject_id = d.subject_id
  AND a.hadm_id    = d.hadm_id
  AND d.seq_num    = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON d.icd_code    = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 72 AND 82
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSPITAL'
  AND a.hospital_expire_flag = 0
  AND LOWER(dd.long_title) LIKE '%unstable angina%';