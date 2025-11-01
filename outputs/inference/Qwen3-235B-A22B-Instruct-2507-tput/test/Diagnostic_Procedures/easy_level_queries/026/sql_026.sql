WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),
procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    ON p.subject_id = proc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE LOWER(d_proc.long_title) LIKE '%catheter ablation%'
     OR LOWER(d_proc.long_title) LIKE '%cardioversion%'
  GROUP BY p.subject_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(250)] AS q25,
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(750)] AS q75
  FROM procedure_counts
)
SELECT
  q75 - q25 AS iqr
FROM percentiles;