WITH acs_codes AS (
  -- list ACS ICD codes (both ICD-9 and ICD-10 formats)
  SELECT '410' AS icd_prefix, 9 AS icd_version UNION ALL
  SELECT '4111', 9 UNION ALL
  SELECT '411' , 9 UNION ALL
  SELECT 'I21' , 10 UNION ALL
  SELECT 'I22' , 10 UNION ALL
  SELECT 'I200', 10
),
acs_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN acs_codes ac
    ON di.icd_version = ac.icd_version
   AND di.icd_code LIKE CONCAT(ac.icd_prefix, '%')
  GROUP BY di.subject_id, di.hadm_id, diagnosis_type
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    ROUND(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24, 2) AS los_days,
    CASE
      WHEN ROUND(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24, 2) BETWEEN 1 AND 4
        THEN '1-4'
      WHEN ROUND(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24, 2) BETWEEN 5 AND 8
        THEN '5-8'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
diagnostic_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS diag_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
   AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%diagnostic%'
  GROUP BY pi.subject_id, pi.hadm_id
),
per_admission AS (
  SELECT
    c.hadm_id,
    c.los_group,
    aa.diagnosis_type,
    COALESCE(dp.diag_proc_count, 0) AS diag_proc_count
  FROM cohort c
  JOIN acs_admissions aa
    ON c.subject_id = aa.subject_id
   AND c.hadm_id = aa.hadm_id
  LEFT JOIN diagnostic_procs dp
    ON c.subject_id = dp.subject_id
   AND c.hadm_id = dp.hadm_id
  WHERE c.los_group IS NOT NULL
)
SELECT
  los_group,
  diagnosis_type,
  APPROX_QUANTILES(diag_proc_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(diag_proc_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(diag_proc_count, 4)[OFFSET(3)] AS p75
FROM per_admission
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;