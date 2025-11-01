WITH mcs_icd_codes AS (
  -- List of mechanical circulatory support ICD-9 codes
  SELECT '37.61' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '37.62', 9 UNION ALL
  SELECT '37.65', 9 UNION ALL
  SELECT '37.66', 9 UNION ALL
  SELECT '39.65', 9
),
female_patients_86_96 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),
mcs_procedures AS (
  SELECT
    p.subject_id,
    proc.hadm_id,
    proc.icd_code,
    proc.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN female_patients_86_96 p
    ON proc.subject_id = p.subject_id
  INNER JOIN mcs_icd_codes mcs
    ON proc.icd_code = mcs.icd_code
    AND proc.icd_version = mcs.icd_version
),
mcs_counts_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_mcs_procedures
  FROM mcs_procedures
  GROUP BY hadm_id
)
SELECT
  quantiles[OFFSET(1)] AS Q1,
  quantiles[OFFSET(3)] AS Q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS IQR
FROM (
  SELECT
    APPROX_QUANTILES(num_mcs_procedures, 4) AS quantiles
  FROM mcs_counts_per_hadm
);