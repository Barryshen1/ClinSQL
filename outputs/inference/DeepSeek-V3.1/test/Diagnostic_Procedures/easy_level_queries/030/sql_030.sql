WITH target_admissions AS (
  SELECT 
    a.hadm_id, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

echo_procedures AS (
  SELECT 
    hadm_id, 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    -- ICD-9 codes
    (icd_version = 9 AND icd_code IN ('88.72', '88.71'))
    OR
    -- ICD-10 codes
    (icd_version = 10 AND icd_code LIKE '4A02X%')
),

echo_counts_per_admission AS (
  SELECT 
    ta.hadm_id,
    COUNT(DISTINCT 
        CONCAT(COALESCE(ep.icd_code, ''), 
               COALESCE(CAST(ep.icd_version AS STRING), ''))
    ) AS distinct_echo_procedures
  FROM target_admissions ta
  LEFT JOIN echo_procedures ep
    ON ta.hadm_id = ep.hadm_id
  GROUP BY ta.hadm_id
)

SELECT 
  APPROX_QUANTILES(distinct_echo_procedures, 100)[OFFSET(25)] AS percentile_25
FROM echo_counts_per_admission;