WITH
-- Filter male patients aged 86-96
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),

-- Identify ablation/cardioversion procedures (example ICD codes)
ablation_cardioversion_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.icd_code,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- Example ICD-9 codes for ablation/cardioversion (adjust as needed)
    p.icd_code IN ('3734', '3733')  -- ICD-9: 37.34 (ablation), 37.33 (cardioversion)
    -- OR p.icd_code IN ('02563ZZ', '02564ZZ')  -- ICD-10 examples
),

-- Count distinct procedures per patient
procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    ablation_cardioversion_procedures
  GROUP BY
    subject_id
)

-- Calculate standard deviation of distinct procedures per patient
SELECT
  STDDEV(distinct_procedure_count) AS sd_distinct_procedures
FROM
  procedure_counts
WHERE
  subject_id IN (SELECT subject_id FROM eligible_patients);