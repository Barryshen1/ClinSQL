SELECT
  COUNT(DISTINCT a.hadm_id) AS index_admissions_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.hadm_id = d.hadm_id
  AND d.seq_num = 1 -- principal diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
ON
  d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  LOWER(dd.long_title) LIKE '%acute pancreatitis%' -- diagnosis is acute pancreatitis (case-insensitive)
  AND p.gender = 'F' -- female patients
  AND p.anchor_age BETWEEN 70 AND 80 -- age 70-80
  AND LOWER(a.insurance) LIKE '%medicare%' -- Medicare insurance (case-insensitive, allows variants)
  AND (
    LOWER(COALESCE(a.admission_location, '')) LIKE '%emergen%' -- admitted from ED (location text)
    OR a.edregtime IS NOT NULL -- or has ED registration time
  );