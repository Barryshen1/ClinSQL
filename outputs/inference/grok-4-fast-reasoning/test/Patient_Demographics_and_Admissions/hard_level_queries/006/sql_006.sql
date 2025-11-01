SELECT
  COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSP.'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code >= '430' AND d.icd_code <= '432')
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
  )
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 36 AND 46;