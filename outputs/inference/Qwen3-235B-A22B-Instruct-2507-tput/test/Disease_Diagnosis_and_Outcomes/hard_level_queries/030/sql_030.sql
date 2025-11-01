WITH age_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 64 AND 74
),

upper_gi_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%upper gastrointestinal bleed%'
     OR LOWER(long_title) LIKE '%hematemesis%'
     OR LOWER(long_title) LIKE '%melena%'
     OR LOWER(long_title) LIKE '%gastrointestinal hemorrhage, upper%'
     OR icd_code IN ('K92.0', 'K92.1', 'K92.2')
),

admissions_with_gi AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN age_filtered af ON a.subject_id = af.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN upper_gi_codes ugc ON di.icd_code = ugc.icd_code
  WHERE di.icd_version = 10
),

diagnosis_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  GROUP BY hadm_id
),

icu_flag AS (
  SELECT 
    hadm_id,
    1 AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  GROUP BY hadm_id
),

composite_score AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    COALESCE(dc.diagnosis_count, 0) AS diag_count,
    COALESCE(icu.had_icu, 0) AS major_complication,
    COALESCE(dc.diagnosis_count, 0) + 20 * COALESCE(icu.had_icu, 0) AS risk_score
  FROM admissions_with_gi a
  LEFT JOIN diagnosis_counts dc ON a.hadm_id = dc.hadm_id
  LEFT JOIN icu_flag icu ON a.hadm_id = icu.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM composite_score
),

mortality_los AS (
  SELECT 
    q.*,
    p.dod,
    -- 30-day mortality: died within 30 days of admission
    CASE 
      WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, q.admittime, DAY) BETWEEN 0 AND 30 
      THEN 1 ELSE 0 
    END AS died_within_30d,
    -- LOS in days
    DATETIME_DIFF(q.dischtime, q.admittime, SECOND) / (24*60*60) AS los_days
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON q.subject_id = p.subject_id
)

SELECT
  risk_quintile,
  COUNT(*) AS n,
  ROUND(AVG(risk_score), 2) AS mean_score,
  ROUND(100.0 * SUM(died_within_30d) / COUNT(*), 2) AS mortality_30d_pct,
  ROUND(100.0 * SUM(major_complication) / COUNT(*), 2) AS major_complication_pct,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY risk_quintile), 2) AS median_los_survivors
FROM mortality_los
WHERE died_within_30d = 0  -- Only survivors for median LOS
GROUP BY risk_quintile, los_days  -- Required for window function
ORDER BY risk_quintile;