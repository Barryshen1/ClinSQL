SELECT
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
   AND d.seq_num    = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
WHERE
  p.gender            = 'F'
  AND p.anchor_age    BETWEEN 79 AND 89
  AND a.insurance     = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND LOWER(dd.long_title) LIKE '%pneumonia%';