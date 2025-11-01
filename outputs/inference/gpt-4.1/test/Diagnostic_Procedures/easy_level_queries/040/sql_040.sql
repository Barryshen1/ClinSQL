WITH ecg_procedure_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ecg%'
     OR LOWER(long_title) LIKE '%electrocardiogram%'
     OR LOWER(long_title) LIKE '%telemetry%'
),
male_patients_51_61 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
ecg_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_ecg_procs
  FROM male_patients_51_61 p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  LEFT JOIN ecg_procedure_codes ecg
    ON pr.icd_code = ecg.icd_code
    AND pr.icd_version = ecg.icd_version
  GROUP BY p.subject_id
)
SELECT
  APPROX_QUANTILES(num_distinct_ecg_procs, 4)[OFFSET(1)] AS ecg_25th_percentile
FROM ecg_counts;