SELECT
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  USING (subject_id, hadm_id)
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  -- identify transfers (admission_type or admission_location text)
  AND (
    a.admission_type = 'TRANSFER'
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
  )
  -- principal diagnosis
  AND d.seq_num = 1
  -- ESRD: ICD-9 585.6 or ICD-10 N18.6 (normalize codes by removing dots)
  AND (
    (SAFE_CAST(d.icd_version AS INT64) = 9 AND REPLACE(d.icd_code, '.', '') = '5856')
    OR (SAFE_CAST(d.icd_version AS INT64) = 10 AND UPPER(REPLACE(d.icd_code, '.', '')) = 'N186')
  );