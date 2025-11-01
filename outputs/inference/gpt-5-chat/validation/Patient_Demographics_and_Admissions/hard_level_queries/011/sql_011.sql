WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    adm.admittime,
    adm.admission_location,
    adm.insurance,
    adm.dischtime,
    diag.icd_code,
    diag.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  WHERE diag.seq_num = 1  -- principal diagnosis
)
SELECT
  COUNT(DISTINCT hadm_id) AS num_index_admissions
FROM
  cohort
WHERE
  gender = 'F'
  AND insurance = 'Medicare'
  AND dischtime IS NOT NULL
  -- admission from emergency department
  AND UPPER(admission_location) LIKE '%EMERGENCY%'
  -- Age at admission between 68 and 78 inclusive
  AND (
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)
  ) BETWEEN 68 AND 78
  -- hemorrhagic stroke ICD9 / ICD10 codes
  AND (
    (icd_version = 9 AND (
      icd_code LIKE '430%' OR
      icd_code LIKE '431%' OR
      icd_code LIKE '432%'
    ))
    OR
    (icd_version = 10 AND (
      icd_code LIKE 'I60%' OR
      icd_code LIKE 'I61%' OR
      icd_code LIKE 'I62%'
    ))
  );