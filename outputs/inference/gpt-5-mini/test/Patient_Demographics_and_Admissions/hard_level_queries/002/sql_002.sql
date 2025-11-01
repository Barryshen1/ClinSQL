SELECT
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.hadm_id = di.hadm_id
  AND di.seq_num = 1  -- principal diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
  ON di.icd_code = dicd.icd_code
  AND di.icd_version = dicd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  AND LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%'
  AND LOWER(dicd.long_title) LIKE '%pneumonia%';