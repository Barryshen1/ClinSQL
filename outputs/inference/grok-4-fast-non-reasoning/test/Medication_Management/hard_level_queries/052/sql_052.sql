WITH base_cohort AS (
  -- Base cohort: females aged 68-78
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
hhs_cohort AS (
  -- HHS admissions (principal diagnosis)
  SELECT 
    bc.*,
    CASE 
      WHEN di.icd_version = '10' AND di.icd_code LIKE 'E11.00%' THEN 1
      WHEN di.icd_version = '9' AND di.icd_code IN ('25020', '25022') THEN 1
      ELSE 0 
    END AS has_hhs
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON bc.hadm_id = di.hadm_id 
    AND SAFE_CAST(di.seq_num AS INT64) = 1  -- Principal diagnosis; cast seq_num to INT64
  WHERE bc.rn = 1  -- First admission
),
meds_72h AS (
  -- Prescriptions within 72h of admit
  SELECT 
    hc.hadm_id,
    hc.has_hhs,
    COUNT(DISTINCT pr.drug) AS med_complexity,
    -- Hyperkalemia-risk drugs (proxy: key classes)
    COUNT(DISTINCT CASE 
      WHEN LOWER(pr.drug) LIKE '%spironolactone%' 
        OR LOWER(pr.drug) LIKE '%eplerenone%' 
        OR LOWER(pr.drug) LIKE '%ace inhibitor%' 
        OR LOWER(pr.drug) LIKE '%arb%' 
        OR LOWER(pr.drug) LIKE '%losartan%' 
        OR LOWER(pr.drug) LIKE '%valsartan%' 
        OR LOWER(pr.drug) LIKE '%potassium%' 
        OR LOWER(pr.drug) LIKE '%kayexalate%'  -- For hyperK treatment, but risk context
      THEN pr.drug 
    END) AS risk_drug_count
  FROM hhs_cohort hc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON hc.hadm_id = pr.hadm_id
    AND pr.starttime >= hc.admittime
    AND pr.starttime < TIMESTAMP_ADD(hc.admittime, INTERVAL 72 HOUR)
  GROUP BY hc.hadm_id, hc.has_hhs
),
metrics AS (
  SELECT 
    hc.has_hhs,
    COALESCE(m.med_complexity, 0) AS med_complexity,
    COALESCE(m.risk_drug_count, 0) AS risk_drug_count,
    -- LOS in days (simplified)
    DATE_DIFF(hc.dischtime, hc.admittime, DAY) AS los_days,
    hc.hospital_expire_flag
  FROM hhs_cohort hc
  LEFT JOIN meds_72h m ON hc.hadm_id = m.hadm_id
),
global_quantiles AS (
  -- Compute global quantiles over all data
  SELECT 
    APPROX_QUANTILES(risk_drug_count, 2)[OFFSET(1)] AS median_risk_all,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS top_quartile_los_all
  FROM metrics
),
hhs_metrics AS (
  -- HHS-specific medians/quantiles
  SELECT 
    APPROX_QUANTILES(risk_drug_count, 2)[OFFSET(1)] AS median_risk_hhs
  FROM metrics
  WHERE has_hhs = 1
),
agg_metrics AS (
  SELECT 
    m.*,
    gq.median_risk_all,
    gq.top_quartile_los_all,
    hhs.median_risk_hhs
  FROM metrics m
  CROSS JOIN global_quantiles gq
  CROSS JOIN hhs_metrics hhs
)
-- Final aggregations
SELECT 
  has_hhs AS cohort,  -- 1 = HHS, 0 = All female inpatients 68-78
  -- 72-hour medication complexity distribution (buckets)
  COUNT(*) AS n_patients,
  COUNT(CASE WHEN med_complexity = 0 THEN 1 END) AS n_complexity_0,
  COUNT(CASE WHEN med_complexity BETWEEN 1 AND 5 THEN 1 END) AS n_complexity_1_5,
  COUNT(CASE WHEN med_complexity BETWEEN 6 AND 10 THEN 1 END) AS n_complexity_6_10,
  COUNT(CASE WHEN med_complexity > 10 THEN 1 END) AS n_complexity_gt10,
  -- Median risk count for HHS (proxy for median percentile rank relative to all)
  ANY_VALUE(CASE WHEN has_hhs = 1 THEN median_risk_hhs END) AS median_risk_hhs,
  -- Percent affected (HHS with >=2 risk drugs)
  SAFE_DIVIDE(COUNT(CASE WHEN has_hhs = 1 AND risk_drug_count >= 2 THEN 1 END), 
              COUNT(CASE WHEN has_hhs = 1 THEN 1 END)) * 100 AS pct_hhs_affected,
  -- Top-quartile LOS (75th %ile all)
  ANY_VALUE(top_quartile_los_all) AS top_quartile_los_all_days,
  SAFE_DIVIDE(COUNT(CASE WHEN has_hhs = 1 AND los_days >= top_quartile_los_all THEN 1 END), 
              COUNT(CASE WHEN has_hhs = 1 THEN 1 END)) * 100 AS pct_hhs_top_quartile_los,
  -- Mortality % for HHS
  SAFE_DIVIDE(COUNT(CASE WHEN has_hhs = 1 AND hospital_expire_flag = 1 THEN 1 END), 
              COUNT(CASE WHEN has_hhs = 1 THEN 1 END)) * 100 AS mortality_pct_hhs
FROM agg_metrics
GROUP BY has_hhs
ORDER BY has_hhs DESC;