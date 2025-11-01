WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
valve_procedures AS (
  SELECT DISTINCT d_icd.long_title, d_icd.icd_code, d_icd.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_icd
  WHERE LOWER(d_icd.long_title) LIKE '%valve%'
    AND (LOWER(d_icd.long_title) LIKE '%repair%'
         OR LOWER(d_icd.long_title) LIKE '%replace%'
         OR LOWER(d_icd.long_title) LIKE '%replacement%')
),
hadm_procedure_counts AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
  INNER JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  INNER JOIN valve_procedures vp ON p.icd_code = vp.icd_code AND p.icd_version = vp.icd_version
  GROUP BY p.hadm_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS q3
  FROM hadm_procedure_counts
)
SELECT
  q3 - q1 AS iqr
FROM percentiles;