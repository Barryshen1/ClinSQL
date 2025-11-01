WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
),

mechanical_support AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN (icd_version = 9 AND icd_code IN ('3768')) OR (icd_version = 10 AND icd_code LIKE '5A02%') THEN 'IABP'
      WHEN (icd_version = 9 AND icd_code IN ('3965')) OR (icd_version = 10 AND icd_code LIKE '5A15%') THEN 'ECMO'
    END AS support_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('3768', '3965'))
    OR 
    (icd_version = 10 AND (icd_code LIKE '5A02%' OR icd_code LIKE '5A15%'))
),

support_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT ms.support_type) AS num_support_types
  FROM cohort c
  LEFT JOIN mechanical_support ms
    ON c.hadm_id = ms.hadm_id
  GROUP BY c.hadm_id
)

SELECT 
  APPROX_QUANTILES(num_support_types, 1000)[OFFSET(250)] AS q1,
  APPROX_QUANTILES(num_support_types, 1000)[OFFSET(750)] AS q3,
  APPROX_QUANTILES(num_support_types, 1000)[OFFSET(750)] - 
  APPROX_QUANTILES(num_support_types, 1000)[OFFSET(250)] AS iqr
FROM support_counts;