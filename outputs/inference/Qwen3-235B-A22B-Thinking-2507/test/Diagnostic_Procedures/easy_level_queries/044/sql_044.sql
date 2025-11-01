WITH mcs_codes AS (
  SELECT '3765' AS icd_code, 9 AS icd_version
  UNION ALL
  SELECT '5A02210', 10
  UNION ALL
  SELECT '5A15220', 10
  UNION ALL
  SELECT '5A15210', 10
  UNION ALL
  SELECT '5A02211', 10
  UNION ALL
  SELECT '5A02221', 10
),
cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 56 AND 66
),
patient_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT CONCAT(p.icd_code, '_', CAST(p.icd_version AS STRING))) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN mcs_codes m
    ON p.icd_code = m.icd_code AND p.icd_version = m.icd_version
  GROUP BY p.subject_id
)
SELECT STDDEV(COALESCE(pp.num_procedures, 0)) AS sd_procedures
FROM cohort c
LEFT JOIN patient_procedures pp
  ON c.subject_id = pp.subject_id;