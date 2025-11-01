WITH
-- Filter patients: males aged 45-55
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),

-- Identify CABG procedures (ICD-9: 36.1x, ICD-10: 02100Z0, etc.)
cabg_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- ICD-9 codes for CABG (36.1x)
    (p.icd_version = 9 AND p.icd_code LIKE '36.1%')
    -- ICD-10 codes for CABG (e.g., 02100Z0)
    OR (p.icd_version = 10 AND p.icd_code LIKE '02100Z%')
),

-- Count distinct CABG procedures per patient
cabg_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_cabg_procedures
  FROM
    cabg_procedures
  GROUP BY
    subject_id
),

-- Include patients with no CABG procedures (count = 0)
all_patients_with_counts AS (
  SELECT
    p.subject_id,
    COALESCE(c.num_cabg_procedures, 0) AS num_cabg_procedures
  FROM
    eligible_patients p
  LEFT JOIN
    cabg_counts c
  ON
    p.subject_id = c.subject_id
)

-- Calculate the 25th percentile
SELECT
  PERCENTILE_CONT(num_cabg_procedures, 0.25) OVER() AS percentile_25
FROM
  all_patients_with_counts
LIMIT 1;