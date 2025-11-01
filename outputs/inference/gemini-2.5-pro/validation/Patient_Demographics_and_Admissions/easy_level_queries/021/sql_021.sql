WITH pneumonia_admissions AS (
  -- First, find all hospital admissions (hadm_id) with a pneumonia diagnosis
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    LOWER(d_diag.long_title) LIKE '%pneumonia%'
),

first_admissions_for_cohort AS (
  -- Next, identify the first admission for each female patient aged 83-93
  SELECT
    p.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY adm.admittime ASC) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
)

-- Finally, calculate the mortality rate for the target cohort
-- which is patients whose first admission was for pneumonia
SELECT
  ROUND(
    100.0 * SUM(cohort.hospital_expire_flag) / COUNT(cohort.subject_id),
    2
  ) AS in_hospital_mortality_percent
FROM
  first_admissions_for_cohort AS cohort
-- Join to ensure the admission was for pneumonia
INNER JOIN
  pneumonia_admissions AS pa
  ON cohort.hadm_id = pa.hadm_id
WHERE
  -- Filter for only the first admission
  cohort.admission_rank = 1;