WITH female_patients_43_53 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),

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
    -- Example ICD-9 codes for mechanical circulatory support (adjust as needed)
    p.icd_code LIKE '39.6%'  -- ECMO
    OR p.icd_code LIKE '39.7%'  -- IABP
    OR p.icd_code LIKE '39.8%'  -- LVAD
    OR p.icd_code LIKE '39.9%'  -- Other circulatory support
    -- Add more codes if needed
),

procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    mechanical_circulatory_support_procedures
  WHERE
    subject_id IN (SELECT subject_id FROM female_patients_43_53)
  GROUP BY
    subject_id
)

SELECT
  PERCENTILE_CONT(distinct_procedure_count, 0.25) OVER() AS percentile_25
FROM
  procedure_counts
LIMIT 1;