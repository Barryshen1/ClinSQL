WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
aki_patients AS (
  SELECT 
    c.*,
    d.icd_code,
    d.icd_version
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE 
    (d.icd_version = 10 AND d.icd_code LIKE 'N17%') 
    OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
),
-- Get all diagnoses for these patients to compute comorbidities and ARDS
all_diagnoses AS (
  SELECT 
    aki.subject_id,
    aki.hadm_id,
    d.icd_code,
    d.icd_version,
    -- Extract chapter from ICD code: first character for ICD-10, first 3 digits for ICD-9?
    -- Actually, for simplicity we use the first character for both (rough)
    CASE 
      WHEN d.icd_version = 10 THEN SUBSTR(d.icd_code, 1, 1)
      WHEN d.icd_version = 9 THEN SUBSTR(d.icd_code, 1, 1)
    END AS chapter
  FROM aki_patients aki
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON aki.hadm_id = d.hadm_id
),
-- Compute comorbidities: count distinct chapters
comorbidities AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT chapter) AS num_chapters
  FROM all_diagnoses
  GROUP BY subject_id, hadm_id
),
-- Check for ARDS
ards AS (
  SELECT 
    aki.subject_id,
    aki.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 10 AND d.icd_code = 'J80') 
               OR (d.icd_version = 9 AND d.icd_code = '518.82') 
          THEN 1 ELSE 0 
        END) AS has_ards
  FROM aki_patients aki
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON aki.hadm_id = d.hadm_id
    AND (
      (d.icd_version = 10 AND d.icd_code = 'J80') 
      OR (d.icd_version = 9 AND d.icd_code = '518.82')
    )
  GROUP BY aki.subject_id, aki.hadm_id
),
-- Combine to compute risk score and precompute LOS for survivors
risk_scores AS (
  SELECT 
    aki.subject_id,
    aki.hadm_id,
    aki.admittime,
    aki.dischtime,
    aki.dod,
    aki.hospital_expire_flag,
    COALESCE(c.num_chapters, 0) AS num_comorbidities,
    COALESCE(ar.has_ards, 0) AS has_ards,
    -- Composite risk: 5 * comorbidities + 50 if ARDS
    5 * COALESCE(c.num_chapters, 0) + CASE WHEN ar.has_ards = 1 THEN 50 ELSE 0 END AS risk_score,
    -- Precompute LOS in days for survivors (only if they did not die in hospital)
    CASE WHEN aki.hospital_expire_flag = 0 THEN DATE_DIFF(DATE(aki.dischtime), DATE(aki.admittime), DAY) ELSE NULL END AS los_days_survivor
  FROM aki_patients aki
  LEFT JOIN comorbidities c
    ON aki.hadm_id = c.hadm_id
  LEFT JOIN ards ar
    ON aki.hadm_id = ar.hadm_id
),
-- Create quintiles based on risk_score
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM risk_scores
),
-- Compute outcomes
outcomes AS (
  SELECT 
    quintile,
    COUNT(*) AS N,
    -- 30-day post-discharge mortality: died within 30 days of discharge and not in-hospital death
    ROUND(100.0 * SUM(CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(dischtime), DAY) <= 30 AND hospital_expire_flag = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_30d_post_discharge_pct,
    -- ARDS co-occurrence %
    ROUND(100.0 * SUM(has_ards) / COUNT(*), 2) AS ards_cooccurrence_pct,
    -- Median survivor LOS (in days) - use APPROX_QUANTILES for grouped aggregation
    APPROX_QUANTILES(los_days_survivor, 100)[OFFSET(50)] AS median_survivor_los_days
  FROM quintiles
  GROUP BY quintile
)
SELECT 
  quintile,
  N,
  mortality_30d_post_discharge_pct,
  ards_cooccurrence_pct,
  median_survivor_los_days
FROM outcomes
ORDER BY quintile;