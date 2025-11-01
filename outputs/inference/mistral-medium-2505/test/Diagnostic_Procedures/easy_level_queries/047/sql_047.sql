WITH
-- Filter male patients aged 37-47
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),

-- Identify ablation/cardioversion procedures
ablation_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    d.long_title AS procedure_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- Filter for ablation/cardioversion procedures (adjust keywords as needed)
    LOWER(d.long_title) LIKE '%ablation%'
    OR LOWER(d.long_title) LIKE '%cardioversion%'
),

-- Count distinct procedures per patient
procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT hadm_id) AS distinct_procedure_count
  FROM
    ablation_procedures
  WHERE
    subject_id IN (SELECT subject_id FROM eligible_patients)
  GROUP BY
    subject_id
)

-- Calculate standard deviation of procedure counts
SELECT
  STDDEV(distinct_procedure_count) AS sd_distinct_procedures
FROM
  procedure_counts;