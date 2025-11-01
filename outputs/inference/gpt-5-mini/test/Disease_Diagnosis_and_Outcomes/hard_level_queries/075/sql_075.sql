WITH
-- 1) Identify intracranial hemorrhage diagnoses by text matching on description
ich_diag_codes AS (
  SELECT DISTINCT di.icd_code, di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  WHERE LOWER(di.long_title) LIKE '%intracran%' 
     OR LOWER(di.long_title) LIKE '%intracerebr%' 
     OR LOWER(di.long_title) LIKE '%subarachnoid%' 
     OR LOWER(di.long_title) LIKE '%subdural%' 
     OR LOWER(di.long_title) LIKE '%epidural%'
     OR LOWER(di.long_title) LIKE '%hemorrhag%'
),

-- 2) Identify complication diagnosis text keywords (pragmatic list)
complication_diag_codes AS (
  SELECT DISTINCT di.icd_code, di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  WHERE LOWER(di.long_title) LIKE '%sepsis%'
     OR LOWER(di.long_title) LIKE '%pneumonia%'
     OR LOWER(di.long_title) LIKE '%acute respiratory%'
     OR LOWER(di.long_title) LIKE '%acute renal%'
     OR LOWER(di.long_title) LIKE '%acute kidney%'
     OR LOWER(di.long_title) LIKE '%acute myocardial%'
     OR LOWER(di.long_title) LIKE '%myocardial infarction%'
     OR LOWER(di.long_title) LIKE '%pulmonary embol%'
     OR LOWER(di.long_title) LIKE '%deep vein%'
     OR LOWER(di.long_title) LIKE '%dvt%'
     OR LOWER(di.long_title) LIKE '%thrombo%'
     OR LOWER(di.long_title) LIKE '%reoperation%'
     OR LOWER(di.long_title) LIKE '%surgical site infection%'
     OR LOWER(di.long_title) LIKE '%seizure%'
     OR LOWER(di.long_title) LIKE '%acute respiratory failure%'
),

-- 3) Per-admission aggregates: diag count and complication flag
diag_agg AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diag_count,
    MAX(
      CASE
        WHEN (
          di.icd_code IN (SELECT icd_code FROM complication_diag_codes WHERE icd_version = di.icd_version)
          OR LOWER(d.long_title) LIKE '%sepsis%'
          OR LOWER(d.long_title) LIKE '%pneumonia%'
          OR LOWER(d.long_title) LIKE '%acute respiratory%' 
          OR LOWER(d.long_title) LIKE '%acute renal%'
          OR LOWER(d.long_title) LIKE '%acute kidney%'
          OR LOWER(d.long_title) LIKE '%myocardial infarction%'
          OR LOWER(d.long_title) LIKE '%pulmonary embol%'
          OR LOWER(d.long_title) LIKE '%deep vein%'
          OR LOWER(d.long_title) LIKE '%dvt%'
          OR LOWER(d.long_title) LIKE '%thrombo%'
          OR LOWER(d.long_title) LIKE '%reoperation%'
          OR LOWER(d.long_title) LIKE '%surgical site infection%'
          OR LOWER(d.long_title) LIKE '%seizure%'
        ) THEN 1 ELSE 0 END
    ) AS comp_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND (d.icd_version IS NULL OR d.icd_version = di.icd_version)
  GROUP BY di.hadm_id
),

-- 4) Base set: female inpatients aged 44-54, compute per-hadm risk_score and flags
admissions_with_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    COALESCE(dg.diag_count, 0) AS risk_score,
    CASE WHEN COALESCE(dg.comp_flag, 0) > 0 THEN 1 ELSE 0 END AS major_complication_flag,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      WHEN p.dod IS NOT NULL AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90 THEN 1
      ELSE 0
    END AS death90,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_agg dg
    ON a.hadm_id = dg.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

-- 5) compute risk percentile (PERCENT_RANK) among the baseline female 44-54 inpatient cohort
admissions_with_percentile AS (
  SELECT
    aws.*,
    PERCENT_RANK() OVER (ORDER BY aws.risk_score) AS risk_pr  -- 0..1
  FROM admissions_with_scores aws
),

-- 6) identify admissions with an intracranial hemorrhage diagnosis (any matched diag on the admission)
ich_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND (d.icd_version IS NULL OR d.icd_version = di.icd_version)
  WHERE (
      LOWER(d.long_title) LIKE '%intracran%'
   OR LOWER(d.long_title) LIKE '%intracerebr%'
   OR LOWER(d.long_title) LIKE '%subarachnoid%'
   OR LOWER(d.long_title) LIKE '%subdural%'
   OR LOWER(d.long_title) LIKE '%epidural%'
   OR LOWER(d.long_title) LIKE '%hemorrhag%' )
),

-- 7) materialize the ICH cohort as its own CTE (avoids referencing an inline alias 'a' inside nested subqueries)
ich_cohort AS (
  SELECT awp.*
  FROM admissions_with_percentile awp
  JOIN ich_admissions ich ON awp.hadm_id = ich.hadm_id
)

-- 8) Aggregations: ICH subset and baseline cohort
SELECT
  cohort,
  n_admissions,
  CONCAT(CAST(risk_median AS STRING), ' (IQR ', CAST(risk_q1 AS STRING), '-', CAST(risk_q3 AS STRING), ')') AS risk_median_iqr,
  ROUND(mortality_90d_pct, 2) AS mortality_90d_pct,
  ROUND(major_complication_pct, 2) AS major_complication_pct,
  CONCAT(CAST(median_survivor_los_days AS STRING), ' (IQR ', CAST(survivor_los_q1 AS STRING), '-', CAST(survivor_los_q3 AS STRING), ') days') AS median_survivor_los_days_iqr,
  CASE
    WHEN median_matched_risk_percentile IS NOT NULL THEN CONCAT(ROUND(median_matched_risk_percentile, 2), '%')
    ELSE NULL
  END AS median_matched_risk_percentile
FROM (
  -- ICH group
  SELECT
    'Female 44-54 with ICH' AS cohort,
    COUNT(*) AS n_admissions,
    -- risk quartiles from the ICH subset
    (SELECT quantiles[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM ich_cohort))) AS risk_median,
    (SELECT quantiles[OFFSET(1)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM ich_cohort))) AS risk_q1,
    (SELECT quantiles[OFFSET(3)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM ich_cohort))) AS risk_q3,
    100.0 * SUM(ich_cohort.death90) / COUNT(*) AS mortality_90d_pct,
    100.0 * SUM(ich_cohort.major_complication_flag) / COUNT(*) AS major_complication_pct,
    -- survivor LOS quartiles (only survivors)
    (SELECT quantiles[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM ich_cohort WHERE hospital_expire_flag = 0))) AS median_survivor_los_days,
    (SELECT quantiles[OFFSET(1)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM ich_cohort WHERE hospital_expire_flag = 0))) AS survivor_los_q1,
    (SELECT quantiles[OFFSET(3)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM ich_cohort WHERE hospital_expire_flag = 0))) AS survivor_los_q3,
    -- median matched risk percentile (0..1 -> percent)
    100.0 * (SELECT quantiles[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(risk_pr, 4) AS quantiles FROM (SELECT risk_pr FROM ich_cohort))) AS median_matched_risk_percentile
  FROM ich_cohort

  UNION ALL

  -- Baseline all female 44-54
  SELECT
    'All female 44-54' AS cohort,
    COUNT(*) AS n_admissions,
    (SELECT quantiles[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM admissions_with_percentile))) AS risk_median,
    (SELECT quantiles[OFFSET(1)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM admissions_with_percentile))) AS risk_q1,
    (SELECT quantiles[OFFSET(3)] FROM (SELECT APPROX_QUANTILES(risk_score, 4) AS quantiles FROM (SELECT risk_score FROM admissions_with_percentile))) AS risk_q3,
    100.0 * SUM(death90) / COUNT(*) AS mortality_90d_pct,
    100.0 * SUM(major_complication_flag) / COUNT(*) AS major_complication_pct,
    (SELECT quantiles[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM admissions_with_percentile WHERE hospital_expire_flag = 0))) AS median_survivor_los_days,
    (SELECT quantiles[OFFSET(1)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM admissions_with_percentile WHERE hospital_expire_flag = 0))) AS survivor_los_q1,
    (SELECT quantiles[OFFSET(3)] FROM (SELECT APPROX_QUANTILES(los_days, 4) AS quantiles FROM (SELECT los_days FROM admissions_with_percentile WHERE hospital_expire_flag = 0))) AS survivor_los_q3,
    NULL AS median_matched_risk_percentile
  FROM admissions_with_percentile
) t
ORDER BY cohort DESC;