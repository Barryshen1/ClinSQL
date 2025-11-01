WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),
target_procedures AS (
  SELECT p.subject_id,
         p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN target_patients tp
    ON p.subject_id = tp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%catheter ablation%'
     OR LOWER(d.long_title) LIKE '%cardioversion%'
),
procedure_counts AS (
  SELECT subject_id,
         COUNT(DISTINCT icd_code) AS proc_count
  FROM target_procedures
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] - APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS iqr
FROM procedure_counts;