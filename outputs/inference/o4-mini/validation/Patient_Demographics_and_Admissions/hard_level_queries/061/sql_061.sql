SELECT
  COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
   AND d.seq_num    = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code    = di.icd_code
   AND d.icd_version = di.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND a.insurance = 'MEDICARE'
  AND LOWER(di.long_title) LIKE '%atrial fibrillation%'
  AND a.admission_location LIKE 'TRANSFER%'
;