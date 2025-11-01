WITH mcs_procedure_codes AS (
  -- Identify ICD procedure codes whose description suggests mechanical circulatory support (ECMO, VAD, IABP, etc.)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE (
    LOWER(long_title) LIKE '%ecmo%' OR
    LOWER(long_title) LIKE '%extracorporeal%' OR
    LOWER(long_title) LIKE '%ventricular assist%' OR
    LOWER(long_title) LIKE '%ventricular-assist%' OR
    LOWER(long_title) LIKE '%ventricular assist device%' OR
    LOWER(long_title) LIKE '%intra-aortic%' OR
    LOWER(long_title) LIKE '%balloon pump%' OR
    LOWER(long_title) LIKE '%iabp%' OR
    LOWER(long_title) LIKE '%cardiac assist%'
  )
),

mcs_counts_by_hadm AS (
  -- Count distinct MCS procedure ICD codes per hospital admission
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_mcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN mcs_procedure_codes m
    ON p.icd_code = m.icd_code
   AND p.icd_version = m.icd_version
  GROUP BY p.hadm_id
),

female_admissions_86_96 AS (
  -- All hospital admissions for female patients aged 86-96 (inclusive)
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON a.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 86 AND 96
)

-- Final aggregation: compute single-row count and quantiles, then select
SELECT
  q.quantiles[OFFSET(25)] AS q1_25,
  q.quantiles[OFFSET(75)] AS q3_75,
  SAFE_CAST(q.quantiles[OFFSET(75)] AS INT64) - SAFE_CAST(q.quantiles[OFFSET(25)] AS INT64) AS iqr_q3_minus_q1,
  cnt.n_hospitalizations_included
FROM (
  -- single-row: count of included admissions
  SELECT COUNT(1) AS n_hospitalizations_included
  FROM female_admissions_86_96
) AS cnt
CROSS JOIN (
  -- single-row: approx percentiles (0..100) of distinct_mcs_count including zeros
  SELECT APPROX_QUANTILES(distinct_mcs_count, 100) AS quantiles
  FROM (
    SELECT COALESCE(m.distinct_mcs_count, 0) AS distinct_mcs_count
    FROM female_admissions_86_96 fa
    LEFT JOIN mcs_counts_by_hadm m
      ON fa.hadm_id = m.hadm_id
  )
) AS q;