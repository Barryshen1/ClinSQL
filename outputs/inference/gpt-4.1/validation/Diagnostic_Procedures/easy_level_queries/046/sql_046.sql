WITH mcs_icd_codes AS (
  -- List of mechanical circulatory support ICD codes (ICD-9 and ICD-10)
  SELECT '37.61' AS icd_code, 9 AS icd_version UNION ALL -- IABP
  SELECT '37.66', 9 UNION ALL -- VAD
  SELECT '39.65', 9 UNION ALL -- ECMO
  SELECT '5A02210', 10 UNION ALL -- IABP
  SELECT '02HA0QZ', 10 UNION ALL -- VAD
  SELECT '02HA0RZ', 10 UNION ALL -- VAD
  SELECT '5A15223', 10 UNION ALL -- ECMO
  SELECT '5A15224', 10 UNION ALL -- ECMO
  SELECT '5A02110', 10 UNION ALL -- Impella
  SELECT '5A02116', 10 -- Impella
),
men_80_90 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),
admissions_men_80_90 AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN men_80_90 p ON a.subject_id = p.subject_id
),
mcs_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    pr.icd_code,
    pr.icd_version
  FROM admissions_men_80_90 p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  INNER JOIN mcs_icd_codes mcs
    ON pr.icd_code = mcs.icd_code AND pr.icd_version = mcs.icd_version
),
distinct_mcs_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_distinct_mcs
  FROM mcs_procedures
  GROUP BY subject_id, hadm_id
),
max_mcs_per_patient AS (
  SELECT
    subject_id,
    MAX(num_distinct_mcs) AS max_mcs_per_admission
  FROM distinct_mcs_per_admission
  GROUP BY subject_id
)
SELECT
  MAX(max_mcs_per_admission) AS max_distinct_mcs_procedures_per_patient
FROM max_mcs_per_patient;