WITH
-- Get female patients aged 86-96
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),

-- Get all hospitalizations for these patients
patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
),

-- Identify mechanical circulatory support procedures
mechanical_circ_support_procedures AS (
  SELECT DISTINCT
    p.hadm_id,
    p.icd_code,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    -- Common ICD-9 codes for mechanical circulatory support
    p.icd_code IN (
      '37.68',  -- Insertion of ventricular assist device
      '37.65',  -- Insertion of intra-aortic balloon pump
      '37.66',  -- Insertion of other cardiac assist device
      '37.67',  -- Insertion of extracorporeal membrane oxygenation [ECMO]
      '37.64'   -- Insertion of implantable heart assist system
    )
    -- For ICD-10, we might need additional codes, but MIMIC-IV primarily uses ICD-9
),

-- Count distinct procedures per hospitalization
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    mechanical_circ_support_procedures
  GROUP BY
    hadm_id
),

-- Calculate IQR statistics
iqr_stats AS (
  SELECT
    PERCENTILE_CONT(distinct_procedure_count, 0.25) OVER() AS q1,
    PERCENTILE_CONT(distinct_procedure_count, 0.75) OVER() AS q3
  FROM
    procedure_counts
  LIMIT 1
)

-- Final result
SELECT
  q1 AS first_quartile,
  q3 AS third_quartile,
  (q3 - q1) AS iqr
FROM
  iqr_stats;