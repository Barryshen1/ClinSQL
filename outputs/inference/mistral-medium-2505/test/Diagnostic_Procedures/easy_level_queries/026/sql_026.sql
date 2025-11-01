WITH
-- Get male patients aged 75-85
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),

-- Get relevant procedure codes (ablation and cardioversion)
relevant_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.icd_code,
    p.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    eligible_patients ep ON p.subject_id = ep.subject_id
  WHERE
    -- Catheter ablation codes
    (p.icd_code IN ('3734', '258300') AND p.icd_version IN ('9', '10'))
    OR
    -- Cardioversion codes
    (p.icd_code IN ('3766', '256300') AND p.icd_version IN ('9', '10'))
),

-- Count distinct procedures per patient
procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(icd_code, icd_version)) AS distinct_procedure_count
  FROM
    relevant_procedures
  GROUP BY
    subject_id
)

-- Calculate IQR
SELECT
  PERCENTILE_CONT(distinct_procedure_count, 0.25) OVER() AS q1,
  PERCENTILE_CONT(distinct_procedure_count, 0.5) OVER() AS median,
  PERCENTILE_CONT(distinct_procedure_count, 0.75) OVER() AS q3,
  PERCENTILE_CONT(distinct_procedure_count, 0.75) OVER() - PERCENTILE_CONT(distinct_procedure_count, 0.25) OVER() AS iqr
FROM
  procedure_counts
LIMIT 1;