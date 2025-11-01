SELECT
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
ON
  a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
ON
  a.hadm_id = d.hadm_id
  AND d.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
ON
  d.icd_code = ddi.icd_code
  AND d.icd_version = ddi.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%skilled nursing%'
  AND LOWER(ddi.long_title) LIKE '%dehydrat%';