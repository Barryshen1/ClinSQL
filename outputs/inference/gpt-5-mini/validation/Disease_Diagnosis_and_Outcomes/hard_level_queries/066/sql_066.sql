WITH
-- Admissions joined to patient demographics
adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE(a.admittime) AS admit_date,
    DATE(a.dischtime) AS discharge_date,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE(p.dod) AS dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- Diagnoses with human-readable titles for pattern matching
diag_long AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    LOWER(di.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    USING(icd_code, icd_version)
),

-- Per-admission comorbidity/risk score and diagnosis flags (PE, AKI, ARDS)
diag_flags AS (
  SELECT
    hadm_id,
    COALESCE(COUNT(DISTINCT icd_code), 0) AS risk_score,
    MAX(CASE WHEN long_title LIKE '%pulmonary embol%' THEN 1 ELSE 0 END) AS pe_flag,
    MAX(CASE WHEN long_title LIKE '%acute kidney%' OR long_title LIKE '%acute renal%' OR long_title LIKE '%acute renal failure%' THEN 1 ELSE 0 END) AS aki_flag,
    MAX(CASE WHEN long_title LIKE '%acute respiratory distress%' OR long_title LIKE '%adult respiratory distress%' OR long_title LIKE '%ards%' THEN 1 ELSE 0 END) AS ards_flag
  FROM diag_long
  GROUP BY hadm_id
),

-- All admissions in our age/gender window that have PE (join diag_flags)
cohort_all AS (
  SELECT
    a.*,
    COALESCE(d.risk_score, 0) AS risk_score,
    COALESCE(d.pe_flag, 0) AS pe_flag,
    COALESCE(d.aki_flag, 0) AS aki_flag,
    COALESCE(d.ards_flag, 0) AS ards_flag
  FROM adm a
  LEFT JOIN diag_flags d USING(hadm_id)
  WHERE COALESCE(d.pe_flag, 0) = 1
),

-- 75th percentile of risk_score among the PE subgroup (approximate)
p75 AS (
  SELECT (APPROX_QUANTILES(risk_score, 100))[OFFSET(75)] AS q75
  FROM cohort_all
),

-- High-comorbidity subgroup: risk_score > 75th percentile
cohort_high AS (
  SELECT c.*
  FROM cohort_all c, p75
  WHERE c.risk_score > p75.q75
),

-- Cohort-level metrics: counts, mean risk score, 90-day mortality
cohort_metrics AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_n_admissions,
    SAFE_CAST(AVG(risk_score) AS FLOAT64) AS cohort_mean_risk_score,
    -- 90-day mortality: death date (dod) on or before discharge_date + 90 days
    SAFE_CAST(SUM(CASE WHEN dod IS NOT NULL AND dod <= DATE_ADD(discharge_date, INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS FLOAT64)
      / NULLIF(COUNT(DISTINCT hadm_id),0) AS cohort_90d_mortality_frac
  FROM cohort_high
),

-- Survivors within the high-comorbidity PE cohort
survivors_cohort AS (
  SELECT *
  FROM cohort_high
  WHERE hospital_expire_flag = 0
),

-- Metrics among survivors in the cohort
survivor_metrics_cohort AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_survivors_n,
    SAFE_CAST(AVG(DATE_DIFF(discharge_date, admit_date, DAY)) AS FLOAT64) AS cohort_survivors_mean_los_days,
    SAFE_CAST(SUM(CASE WHEN aki_flag = 1 THEN 1 ELSE 0 END) AS FLOAT64) / NULLIF(COUNT(DISTINCT hadm_id),0) AS cohort_survivors_aki_rate_frac,
    SAFE_CAST(SUM(CASE WHEN ards_flag = 1 THEN 1 ELSE 0 END) AS FLOAT64) / NULLIF(COUNT(DISTINCT hadm_id),0) AS cohort_survivors_ards_rate_frac
  FROM survivors_cohort
),

-- All male inpatients age 81-91 (for comparison)
all_inpatients AS (
  SELECT
    a.hadm_id,
    a.admit_date,
    a.discharge_date,
    a.hospital_expire_flag,
    COALESCE(d.risk_score, 0) AS risk_score,
    COALESCE(d.aki_flag, 0) AS aki_flag,
    COALESCE(d.ards_flag, 0) AS ards_flag
  FROM adm a
  LEFT JOIN diag_flags d USING(hadm_id)
),

-- Survivors among all inpatients (for comparison)
survivors_all AS (
  SELECT *
  FROM all_inpatients
  WHERE hospital_expire_flag = 0
),

-- Metrics among survivors for all inpatients
survivor_metrics_all AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS all_survivors_n,
    SAFE_CAST(AVG(DATE_DIFF(discharge_date, admit_date, DAY)) AS FLOAT64) AS all_survivors_mean_los_days,
    SAFE_CAST(SUM(CASE WHEN aki_flag = 1 THEN 1 ELSE 0 END) AS FLOAT64) / NULLIF(COUNT(DISTINCT hadm_id),0) AS all_survivors_aki_rate_frac,
    SAFE_CAST(SUM(CASE WHEN ards_flag = 1 THEN 1 ELSE 0 END) AS FLOAT64) / NULLIF(COUNT(DISTINCT hadm_id),0) AS all_survivors_ards_rate_frac
  FROM survivors_all
),

-- Matched-profile risk percentile: percentile rank of cohort mean risk score among all inpatients
risk_percentile AS (
  SELECT
    cm.cohort_mean_risk_score,
    100.0 * SUM(CASE WHEN ai.risk_score <= cm.cohort_mean_risk_score THEN 1 ELSE 0 END) / NULLIF(COUNT(*) , 0) AS matched_profile_percentile
  FROM all_inpatients ai
  CROSS JOIN cohort_metrics cm
  GROUP BY cm.cohort_mean_risk_score
)

-- Final combined results
SELECT
  cm.cohort_n_admissions AS cohort_n_admissions,
  cm.cohort_mean_risk_score AS cohort_mean_risk_score,
  ROUND(100.0 * cm.cohort_90d_mortality_frac, 2) AS cohort_90d_mortality_pct,
  smc.cohort_survivors_n AS cohort_survivors_n,
  ROUND(smc.cohort_survivors_mean_los_days, 2) AS cohort_survivors_mean_los_days,
  ROUND(100.0 * smc.cohort_survivors_aki_rate_frac, 2) AS cohort_survivors_aki_rate_pct,
  ROUND(100.0 * smc.cohort_survivors_ards_rate_frac, 2) AS cohort_survivors_ards_rate_pct,
  sma.all_survivors_n AS all_survivors_n,
  ROUND(sma.all_survivors_mean_los_days, 2) AS all_survivors_mean_los_days,
  ROUND(100.0 * sma.all_survivors_aki_rate_frac, 2) AS all_survivors_aki_rate_pct,
  ROUND(100.0 * sma.all_survivors_ards_rate_frac, 2) AS all_survivors_ards_rate_pct,
  ROUND(rp.matched_profile_percentile, 2) AS matched_profile_risk_percentile,
  p75.q75 AS risk_score_75th_percentile_in_PE_subgroup
FROM cohort_metrics cm
CROSS JOIN survivor_metrics_cohort smc
CROSS JOIN survivor_metrics_all sma
CROSS JOIN risk_percentile rp
CROSS JOIN p75
LIMIT 1;