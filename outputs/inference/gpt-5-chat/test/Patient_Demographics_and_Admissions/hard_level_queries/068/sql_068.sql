SELECT
  COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON adm.subject_id = dx.subject_id
  AND adm.hadm_id = dx.hadm_id
WHERE
  -- male
  pat.gender = 'M'
  -- age 43 to 53 inclusive
  AND pat.anchor_age BETWEEN 43 AND 53
  -- Medicare
  AND LOWER(adm.insurance) = 'medicare'
  -- admitted from SNF
  AND (
    LOWER(adm.admission_location) LIKE '%skilled nursing%'
    OR LOWER(adm.admission_location) LIKE '%snf%'
  )
  -- principal diagnosis only
  AND dx.seq_num = 1
  -- dehydration ICD codes (ICD-9/ICD-10)
  AND (
    (dx.icd_version = 9 AND dx.icd_code = '27651')
    OR (dx.icd_version = 10 AND dx.icd_code LIKE 'E86%')
  );