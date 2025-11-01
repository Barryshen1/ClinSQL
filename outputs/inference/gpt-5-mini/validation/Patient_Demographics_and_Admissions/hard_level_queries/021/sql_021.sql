SELECT
  COUNT(DISTINCT a.hadm_id) AS admissions_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  -- female patients aged 82-92
  p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92

  -- Medicare as payer (case-insensitive)
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'

  -- admitted from the emergency department (admission_location mentions 'emergency' or has ED registration time)
  AND (
    LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
    OR a.edregtime IS NOT NULL
  )

  -- has a recorded discharge
  AND a.dischtime IS NOT NULL

  -- principal diagnosis = acute pancreatitis (ICD-9 577.0 or ICD-10 K85*)
  AND d.seq_num = 1
  AND (
    (SAFE_CAST(d.icd_version AS INT64) = 9 AND d.icd_code = '577.0')
    OR (SAFE_CAST(d.icd_version AS INT64) = 10 AND UPPER(COALESCE(d.icd_code, '')) LIKE 'K85%')
  )
;