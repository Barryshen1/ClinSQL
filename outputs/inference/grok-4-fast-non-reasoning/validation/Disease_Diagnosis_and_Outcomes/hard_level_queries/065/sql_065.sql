WITH elixhauser_weights AS (
  -- Simplified Elixhauser van Walraven weights (common categories)
  SELECT 'PARALYSIS' AS category, 3 AS weight
  UNION ALL SELECT 'MYOCARDIAL_INFARCT', -1
  UNION ALL SELECT 'CHF', 2
  UNION ALL SELECT 'CEREBROVASCULAR', 2
  UNION ALL SELECT 'COPD', 1
  UNION ALL SELECT 'DIABETES_UNCOMPLICATED', 0
  UNION ALL SELECT 'DIABETES_COMPLICATED', 2
  UNION ALL SELECT 'HYPOTENSION', 2
  UNION ALL SELECT 'RENAL', 2
  UNION ALL SELECT 'LIVER', 3
  UNION ALL SELECT 'HIV', 6
  -- Add more as needed; this covers basics
),
elixhauser_icds AS (
  -- ICD-10 mappings to Elixhauser (simplified; fixed patterns for BigQuery LIKE matching)
  SELECT 'I82.4%' AS icd_pattern, 'DVT' AS category  -- For DVT filter
  UNION ALL SELECT 'G81%', 'PARALYSIS'
  UNION ALL SELECT 'I21%', 'MYOCARDIAL_INFARCT'
  UNION ALL SELECT 'I50%', 'CHF'
  UNION ALL SELECT 'I6%', 'CEREBROVASCULAR'  -- I60-I69 approximate
  UNION ALL SELECT 'J4%', 'COPD'  -- J40-J47 approximate
  UNION ALL SELECT 'E10%-E14% AND NOT LIKE "%.7"', 'DIABETES_UNCOMPLICATED'  -- Approximate; note: complex filter, simplified
  UNION ALL SELECT 'E%.7', 'DIABETES_COMPLICATED'  -- E10.7-E14.7 approximate
  -- Expand with full mappings (e.g., from MIMIC code repo)
),
cohort_base AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = p.subject_id 
        AND di.hadm_id = a.hadm_id 
        AND di.icd_code LIKE 'I82.4%' 
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS is_dvt_cohort
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE a.admittime >= '2012-01-01'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),
comorbidities AS (
  SELECT 
    cb.subject_id,
    cb.hadm_id,
    cb.anchor_age,
    cb.admittime,
    cb.dischtime,
    cb.hospital_expire_flag,
    cb.dod,
    cb.is_dvt_cohort,
    COALESCE(SUM(DISTINCT ew.weight), 0) AS elixhauser_score  -- DISTINCT to avoid overcounting per category
  FROM cohort_base cb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON cb.subject_id = di.subject_id AND cb.hadm_id = di.hadm_id AND di.icd_version = '10'
  LEFT JOIN elixhauser_icds ei ON di.icd_code LIKE ei.icd_pattern
  LEFT JOIN elixhauser_weights ew ON ei.category = ew.category
  GROUP BY 
    cb.subject_id, cb.hadm_id, cb.anchor_age, cb.admittime, cb.dischtime, 
    cb.hospital_expire_flag, cb.dod, cb.is_dvt_cohort
),
-- Compute outcomes for DVT high-comorb cohort
dvt_outcomes AS (
  SELECT 
    c.*,
    -- 90-day mortality (hospital or post-discharge within 90 days)
    CASE 
      WHEN c.dod IS NOT NULL 
           AND DATE_DIFF(DATE(c.dod), DATE(c.admittime), DAY) <= 90 
      THEN 1 ELSE 0 
    END AS mortality_90d,
    -- Major complications (e.g., PE, bleeding, stroke as secondary dx)
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc 
        WHERE dc.subject_id = c.subject_id 
          AND dc.hadm_id = c.hadm_id 
          AND dc.seq_num > 1 
          AND dc.icd_version = '10'
          AND (dc.icd_code LIKE 'I26.%' OR  -- PE
               dc.icd_code LIKE 'K92.2%' OR dc.icd_code LIKE 'I61.%' OR  -- Bleeding
               dc.icd_code LIKE 'I63.%')     -- Stroke
      ) THEN 1 ELSE 0 
    END AS major_complication,
    -- LOS for survivors (hospital LOS if not expired in-hospital)
    CASE 
      WHEN c.hospital_expire_flag = 0 
      THEN DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) 
      ELSE NULL 
    END AS survivor_los
  FROM comorbidities c
  WHERE c.is_dvt_cohort = 1 AND c.elixhauser_score >= 3  -- High comorbidity
),
-- Compute outcomes for general population (non-DVT males 71-81)
general_outcomes AS (
  SELECT 
    c.*,
    -- Reuse same outcome logic
    CASE 
      WHEN c.dod IS NOT NULL 
           AND DATE_DIFF(DATE(c.dod), DATE(c.admittime), DAY) <= 90 
      THEN 1 ELSE 0 
    END AS mortality_90d,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc 
        WHERE dc.subject_id = c.subject_id 
          AND dc.hadm_id = c.hadm_id 
          AND dc.seq_num > 1 
          AND dc.icd_version = '10'
          AND (dc.icd_code LIKE 'I26.%' OR  -- PE
               dc.icd_code LIKE 'K92.2%' OR dc.icd_code LIKE 'I61.%' OR  -- Bleeding
               dc.icd_code LIKE 'I63.%')     -- Stroke
      ) THEN 1 ELSE 0 
    END AS major_complication,
    CASE 
      WHEN c.hospital_expire_flag = 0 
      THEN DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) 
      ELSE NULL 
    END AS survivor_los
  FROM comorbidities c
  WHERE c.is_dvt_cohort = 0
),
-- Patient percentile (hardcoded score=5 vs DVT cohort)
patient_percentile AS (
  SELECT 
    5 AS patient_score,
    PERCENT_RANK() OVER (ORDER BY elixhauser_score) * 100 AS cohort_scores_for_rank  -- Compute ranks for all cohort scores
  FROM dvt_outcomes
)
-- Cohort summaries (fixed BigQuery PERCENTILE_CONT syntax)
SELECT 
  'DVT High Comorbidity Cohort' AS group_name,
  COUNT(DISTINCT hadm_id) AS n_patients,
  PERCENTILE_CONT(elixhauser_score, 0.5) OVER (ORDER BY elixhauser_score) AS median_elixhauser,
  PERCENTILE_CONT(elixhauser_score, 0.25) OVER (ORDER BY elixhauser_score) AS iqr_elixhauser_25,
  PERCENTILE_CONT(elixhauser_score, 0.75) OVER (ORDER BY elixhauser_score) AS iqr_elixhauser_75,
  AVG(mortality_90d) AS mortality_90d_rate,
  AVG(major_complication) AS major_complication_rate,
  PERCENTILE_CONT(survivor_los, 0.5) OVER (ORDER BY survivor_los) AS median_survivor_los
FROM dvt_outcomes

UNION ALL

SELECT 
  'General Male 71-81 Inpatients' AS group_name,
  COUNT(DISTINCT hadm_id) AS n_patients,
  PERCENTILE_CONT(elixhauser_score, 0.5) OVER (ORDER BY elixhauser_score) AS median_elixhauser,
  PERCENTILE_CONT(elixhauser_score, 0.25) OVER (ORDER BY elixhauser_score) AS iqr_elixhauser_25,
  PERCENTILE_CONT(elixhauser_score, 0.75) OVER (ORDER BY elixhauser_score) AS iqr_elixhauser_75,
  AVG(mortality_90d) AS mortality_90d_rate,
  AVG(major_complication) AS major_complication_rate,
  PERCENTILE_CONT(survivor_los, 0.5) OVER (ORDER BY survivor_los) AS median_survivor_los
FROM general_outcomes

UNION ALL

-- Patient-specific: 76yo man with assumed score=5; percentile vs DVT cohort
SELECT 
  'Patient Risk Percentile' AS group_name,
  1 AS n_patients,
  5 AS patient_elixhauser,
  NULL AS iqr_elixhauser_25,
  NULL AS iqr_elixhauser_75,
  -- Approximate percentile by finding rank of 5 in cohort scores
  (SELECT PERCENTILE_CONT(elixhauser_score, 0.5) OVER (ORDER BY elixhauser_score) FROM dvt_outcomes WHERE elixhauser_score >= 5 LIMIT 1) * 100 AS risk_percentile_approx,  -- Simplified; use full PERCENT_RANK in prod
  NULL AS mortality_90d_rate,
  NULL AS major_complication_rate,
  NULL AS median_survivor_los
FROM (SELECT 1 AS dummy)  -- Single row for patient
ORDER BY 1;