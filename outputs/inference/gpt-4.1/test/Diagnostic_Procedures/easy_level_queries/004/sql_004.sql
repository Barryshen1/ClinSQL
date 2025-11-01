WITH cabg_codes AS (
  -- Identify CABG procedure codes from ICD dictionary
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%bypass%' AND LOWER(long_title) LIKE '%coronary%'
),
female_41_51 AS (
  -- Get all female patients aged 41-51
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),
cabg_procs AS (
  -- All CABG procedures for female patients 41-51
  SELECT
    p.subject_id,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN cabg_codes c
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
  INNER JOIN female_41_51 f
    ON p.subject_id = f.subject_id
),
cabg_counts AS (
  -- For each patient, count distinct CABG procedures
  SELECT
    f.subject_id,
    COUNT(DISTINCT cp.icd_code) AS cabg_count
  FROM female_41_51 f
  LEFT JOIN cabg_procs cp
    ON f.subject_id = cp.subject_id
  GROUP BY f.subject_id
)
SELECT
  STDDEV_SAMP(cabg_count) AS stddev_cabg_per_patient
FROM cabg_counts
;