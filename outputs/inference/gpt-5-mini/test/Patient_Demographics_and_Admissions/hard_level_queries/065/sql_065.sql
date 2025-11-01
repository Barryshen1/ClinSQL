SELECT
  COUNT(DISTINCT a.hadm_id) AS admissions_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
  AND d.seq_num = 1  -- principal diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON d.icd_code = dicd.icd_code
  AND d.icd_version = dicd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 72 AND 82
  AND a.insurance = 'Medicare'
  AND a.dischtime IS NOT NULL
  -- transferred from another hospital (case-insensitive pattern match)
  AND REGEXP_CONTAINS(UPPER(COALESCE(a.admission_location, '')), r'TRANSFER.*HOSPITAL')
  -- principal diagnosis is unstable angina (case-insensitive)
  AND REGEXP_CONTAINS(LOWER(COALESCE(dicd.long_title, '')), r'unstable\s+angina')
;