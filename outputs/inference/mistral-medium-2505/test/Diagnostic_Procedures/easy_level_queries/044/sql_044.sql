WITH
-- Filter male patients aged 56-66
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),

-- Get mechanical circulatory support procedures (example: ICD-9 37.6X)
mechanical_circulatory_support_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- Example: ICD-9 codes for mechanical circulatory support (adjust as needed)
    p.icd_code LIKE '37.6%'
    -- Include other relevant codes if needed
),

-- Count distinct procedures per patient
procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    mechanical_circulatory_support_procedures
  WHERE
    subject_id IN (SELECT subject_id FROM eligible_patients)
  GROUP BY
    subject_id
)

-- Calculate standard deviation of distinct procedure counts
SELECT
  STDDEV(distinct_procedure_count) AS sd_distinct_mechanical_circulatory_support_procedures
FROM
  procedure_counts;