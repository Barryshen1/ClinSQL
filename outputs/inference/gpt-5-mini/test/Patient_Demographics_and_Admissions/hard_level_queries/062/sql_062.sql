SELECT
  COUNT(DISTINCT a.hadm_id) AS index_admissions_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  USING(subject_id, hadm_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON di.icd_code = d.icd_code
  AND di.icd_version = d.icd_version
WHERE
  -- female patients (case-insensitive)
  LOWER(COALESCE(p.gender, '')) LIKE 'f%'
  -- age between 38 and 48 (inclusive)
  AND p.anchor_age BETWEEN 38 AND 48
  -- Medicare insurance (case-insensitive, allow variations)
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  -- admitted from emergency (either admission_type or admission_location)
  AND (
    a.admission_type = 'EMERGENCY'
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
  )
  -- principal diagnosis = seq_num 1 and diagnosis text indicates acute cholecystitis
  AND di.seq_num = 1
  AND LOWER(COALESCE(d.long_title, '')) LIKE '%acute cholecystitis%';