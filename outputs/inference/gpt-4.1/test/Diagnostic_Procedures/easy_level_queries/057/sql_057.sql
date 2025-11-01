WITH cardiac_catheterization_codes AS (
  -- Get ICD codes for cardiac catheterization procedures
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%catheterization%'
     OR LOWER(long_title) LIKE '%arteriography%'
),
female_patients_64_74 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),
catheterization_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS num_catheterizations
  FROM female_patients_64_74 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN cardiac_catheterization_codes ccc
    ON proc.icd_code = ccc.icd_code
    AND proc.icd_version = ccc.icd_version
  GROUP BY p.subject_id
)
SELECT
  MIN(num_catheterizations) AS min_catheterizations_per_patient
FROM catheterization_counts;