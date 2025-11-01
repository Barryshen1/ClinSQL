WITH afib_codes AS (
  -- First, find all ICD codes related to "Atrial Fibrillation"
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    LOWER(long_title) LIKE '%atrial fibrillation%'
)
SELECT
  COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
INNER JOIN
  afib_codes
  ON diag.icd_code = afib_codes.icd_code AND diag.icd_version = afib_codes.icd_version
WHERE
  -- Patient criteria
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 63 AND 73
  -- Admission criteria
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  -- Filter for inpatient admissions, excluding observation and same-day surgery
  AND adm.admission_type IN ('URGENT', 'EMERGENCY', 'ELECTIVE', 'DIRECT EMER', 'EW EMER')
  -- Diagnosis criteria: Must be the principal diagnosis
  AND diag.seq_num = 1;