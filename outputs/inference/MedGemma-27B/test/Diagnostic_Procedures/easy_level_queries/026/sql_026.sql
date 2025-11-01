WITH relevant_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%cardioversion%'
    OR d.long_title LIKE '%ablation%'
), procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM relevant_procedures
  GROUP BY
    subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS iqr_lower_quartile,
  PERCENTILE_CONT(0.75, distinct_procedure_count) AS iqr_upper_quartile
FROM procedure_counts
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M' AND anchor_age BETWEEN 75 AND 85
  );