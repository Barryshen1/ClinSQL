WITH cci_weights AS (
  -- Simplified patterns for basic comorbidity proxy (not full CCI)
  SELECT * FROM (
    SELECT 'I21%' AS icd_pattern, 'MI' AS category UNION ALL
    SELECT 'I50%', 'CHF' UNION ALL
    SELECT 'I11.0', 'CHF' UNION ALL
    SELECT 'E10%', 'DM' UNION ALL
    SELECT 'E11%', 'DM' UNION ALL
    SELECT 'C%', 'Cancer' UNION ALL
    SELECT 'D0%', 'Cancer'
  )
),
patient_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod,
    CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(CAST(p.dod AS DATE), CAST(a.admittime AS DATE), DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90d
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (d.icd_code LIKE 'I26%' OR (d.icd_version = '9' AND d.icd_code IN ('415.1', '415.11', '415.19')))
    AND a.admittime >= '2008-01-01'
    AND p.anchor_age >= 18
),
all_inpatients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod,
    CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(CAST(p.dod AS DATE), CAST(a.admittime AS DATE), DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90d,
    'all' AS cohort_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 18
    AND a.admittime >= '2008-01-01'
),
combined_cohorts AS (
  SELECT *, 'target' AS cohort_type FROM patient_cohort
  UNION ALL
  SELECT * FROM all_inpatients
),
cci_calc AS (
  SELECT c.*, 
    COALESCE(SUM(CASE 
      WHEN diag.icd_code LIKE 'I21%' THEN 1  -- MI
      WHEN diag.icd_code LIKE 'I50%' OR diag.icd_code = 'I11.0' THEN 1  -- CHF
      WHEN diag.icd_code LIKE 'E1[0-3]%' THEN 1  -- DM
      WHEN diag.icd_code LIKE 'C%' OR diag.icd_code LIKE 'D0%' THEN 2  -- Cancer
      ELSE 0 END), 0) AS cci_score
  FROM combined_cohorts c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON c.hadm_id = diag.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.anchor_age, c.admittime, c.dischtime, c.hospital_expire_flag, 
    c.dod, c.mortality_90d, c.cohort_type
),
percentiles AS (
  SELECT *,
    PERCENTILE_CONT(cci_score, 0.75) OVER (PARTITION BY cohort_type) AS p75_threshold,
    PERCENT_RANK() OVER (PARTITION BY cohort_type ORDER BY cci_score) * 100 AS risk_percentile
  FROM cci_calc
),
aki_flags AS (
  SELECT p.hadm_id,
    MAX(CASE WHEN l.itemid IN (50912, 50976, 51006) 
      AND l.valuenum >= 0.3 
      AND DATETIME_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 48
    THEN 1 ELSE 0 END) AS aki_flag
  FROM percentiles p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON p.hadm_id = l.hadm_id
    AND l.itemid IN (50912, 50976, 51006)
    AND DATETIME_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 168
  GROUP BY p.hadm_id
),
ards_flags AS (
  SELECT p.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'J80%' THEN 1 ELSE 0 END) AS ards_flag
  FROM percentiles p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.hadm_id = d.hadm_id
  GROUP BY p.hadm_id
),
los_calc AS (
  SELECT cc.*,
    DATE_DIFF(CAST(cc.dischtime AS DATE), CAST(cc.admittime AS DATE), DAY) AS los_days,
    CASE WHEN cc.dod IS NULL OR DATE_DIFF(CAST(cc.dod AS DATE), CAST(cc.admittime AS DATE), DAY) > 90 THEN 1 ELSE 0 END AS survivor_flag,
    COALESCE(af.aki_flag, 0) AS aki_flag,
    COALESCE(ards.ards_flag, 0) AS ards_flag
  FROM percentiles cc
  LEFT JOIN aki_flags af ON cc.hadm_id = af.hadm_id
  LEFT JOIN ards_flags ards ON cc.hadm_id = ards.hadm_id
),
high_comorb AS (
  SELECT 
    CASE WHEN cohort_type = 'target' AND cci_score > p75_threshold THEN 'target_high' ELSE cohort_type END AS cohort_type_adj,
    cci_score, mortality_90d, aki_flag, ards_flag, los_days, survivor_flag, risk_percentile, p75_threshold, anchor_age
  FROM los_calc
)
-- Aggregates
SELECT 
  cohort_type_adj AS cohort_type,
  COUNT(*) AS n_patients,
  ROUND(AVG(cci_score), 2) AS mean_risk_score,
  ROUND(p75_threshold, 2) AS high_comorbidity_threshold,
  ROUND(AVG(CASE WHEN mortality_90d = 1 THEN 1.0 ELSE 0 END), 3) AS mortality_90d_rate,
  -- High comorb subanalysis (for target)
  ROUND(AVG(CASE WHEN cohort_type_adj = 'target_high' THEN cci_score ELSE NULL END), 2) AS mean_risk_high_comorb,
  ROUND(AVG(CASE WHEN cohort_type_adj = 'target_high' THEN CASE WHEN mortality_90d = 1 THEN 1.0 ELSE 0 END ELSE NULL END), 3) AS mortality_90d_high_comorb,
  -- Comparisons (rates across cohort)
  ROUND(AVG(CASE WHEN aki_flag = 1 THEN 1.0 ELSE 0 END), 3) AS aki_rate,
  ROUND(AVG(CASE WHEN ards_flag = 1 THEN 1.0 ELSE 0 END), 3) AS ards_rate,
  ROUND(AVG(CASE WHEN survivor_flag = 1 THEN los_days ELSE NULL END), 1) AS mean_los_survivors,
  ROUND(AVG(los_days), 1) AS mean_los_all,
  -- 86yo matched profile percentile (approx using target cohort distribution)
  ROUND(PERCENTILE_CONT(risk_percentile, 0.5) OVER (PARTITION BY CASE WHEN cohort_type_adj = 'target' AND anchor_age = 86 THEN 1 ELSE 0 END), 1) AS risk_percentile_86yo_approx
FROM high_comorb
WHERE cohort_type_adj IN ('target_high', 'target', 'all')
GROUP BY cohort_type_adj, p75_threshold
ORDER BY cohort_type_adj;