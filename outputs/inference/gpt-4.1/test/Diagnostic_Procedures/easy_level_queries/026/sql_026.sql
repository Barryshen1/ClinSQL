WITH male_75_85 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),
target_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%catheter ablation%'
     OR LOWER(long_title) LIKE '%cardioversion%'
),
patient_proc_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_procs
  FROM male_75_85 p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  LEFT JOIN target_procedures tp
    ON pr.icd_code = tp.icd_code
    AND pr.icd_version = tp.icd_version
  GROUP BY p.subject_id
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_num_distinct_procs
FROM (
  SELECT APPROX_QUANTILES(num_distinct_procs, 4) AS quantiles
  FROM patient_proc_counts
);