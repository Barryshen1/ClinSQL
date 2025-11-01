WITH patients_43_53_f AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
mcs_procedures AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE long_title LIKE '%mechanical circulatory support%'
),
procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_mcs_procedures
  FROM patients_43_53_f p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
    AND pr.icd_code IN (SELECT icd_code FROM mcs_procedures)
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE(distinct_mcs_procedures, 0.25) AS p25_distinct_mcs_procedures
FROM procedure_counts;