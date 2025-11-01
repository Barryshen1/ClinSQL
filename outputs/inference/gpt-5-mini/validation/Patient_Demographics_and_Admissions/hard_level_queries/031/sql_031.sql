SELECT
  COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 62 AND 72
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  AND (
    a.edregtime IS NOT NULL
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%'
  )
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND REGEXP_REPLACE(COALESCE(d.icd_code, ''), r'\.', '') = '7802')
    OR (d.icd_version = 10 AND UPPER(COALESCE(d.icd_code, '')) = 'R55')
  );