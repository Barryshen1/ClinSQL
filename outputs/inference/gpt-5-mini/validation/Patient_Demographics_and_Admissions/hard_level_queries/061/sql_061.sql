SELECT
  COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id
  AND di.seq_num = 1  -- principal diagnosis for the admission
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  LOWER(p.gender) = 'f'
  AND p.anchor_age BETWEEN 63 AND 73
  AND LOWER(a.insurance) LIKE '%medicare%'
  -- require admission_location to indicate a transfer from a hospital (case-insensitive)
  AND REGEXP_CONTAINS(LOWER(COALESCE(a.admission_location, '')), r'transfer')
  AND REGEXP_CONTAINS(LOWER(COALESCE(a.admission_location, '')), r'hosp')
  -- principal diagnosis is atrial fibrillation (catch common textual variants)
  AND LOWER(dd.long_title) LIKE '%atrial fibrillation%';