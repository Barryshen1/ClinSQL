SELECT
  COUNT(DISTINCT a.hadm_id) AS index_admission_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1  -- principal diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 70 AND 80
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY'
  AND LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
;