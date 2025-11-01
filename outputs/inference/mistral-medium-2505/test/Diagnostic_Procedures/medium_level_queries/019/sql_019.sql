WITH
-- Get male patients aged 42-52 with acute pancreatitis
pancreatitis_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND (
      -- ICD-9 code for acute pancreatitis
      (d.icd_version = 9 AND d.icd_code = '5770')
      OR
      -- ICD-10 codes for acute pancreatitis (K85.x)
      (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
    )
),

-- Count diagnostic procedures per admission
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE
    -- Filter for diagnostic procedures (ICD-9/10 procedure codes)
    -- This is a simplified approach - in practice you might need more specific filtering
    p.icd_code IS NOT NULL
  GROUP BY
    hadm_id
),

-- Combine with LOS categories
los_with_procedures AS (
  SELECT
    pp.hadm_id,
    pp.los_days,
    CASE
      WHEN pp.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN pp.los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_category,
    COALESCE(pc.procedure_count, 0) AS procedure_count
  FROM
    pancreatitis_patients pp
  LEFT JOIN
    procedure_counts pc ON pp.hadm_id = pc.hadm_id
  WHERE
    pp.los_days BETWEEN 1 AND 7
)

-- Final aggregation
SELECT
  los_category,
  COUNT(DISTINCT hadm_id) AS patient_count,
  ROUND(AVG(procedure_count), 2) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM
  los_with_procedures
WHERE
  los_category IS NOT NULL
GROUP BY
  los_category
ORDER BY
  los_category;