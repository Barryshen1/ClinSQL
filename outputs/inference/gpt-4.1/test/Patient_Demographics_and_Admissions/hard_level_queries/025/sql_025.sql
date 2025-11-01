SELECT
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 65 AND 75
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
  AND (
    LOWER(dd.long_title) LIKE '%heart failure%'
    OR (
      -- fallback for common ICD codes if long_title mapping is incomplete
      (d.icd_version = 9 AND (d.icd_code LIKE '428%' OR d.icd_code = '39891'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
  );