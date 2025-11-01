SELECT
  COUNT(DISTINCT a.hadm_id) AS admissions_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  AND d.seq_num = 1  -- principal diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
  ON d.icd_code = ddi.icd_code
  AND d.icd_version = ddi.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 79 AND 89
  AND LOWER(a.insurance) LIKE '%medicare%'
  AND LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%'
  AND LOWER(COALESCE(ddi.long_title, '')) LIKE '%pneumonia%';