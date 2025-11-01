WITH all_females AS (
  -- All females aged 43-53 with ICU stay
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_year,
    -- Proxy risk score: anchor_age + normalized ICU LOS (capped at 30 days)
    p.anchor_age + COALESCE(SUM(i.los) / 24.0, 0) / 30.0 AS risk_score_proxy,
    -- 30-day mortality flag (from admission)
    CASE 
      WHEN a.deathtime IS NOT NULL AND DATE_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN a.deathtime IS NULL AND p.dod IS NOT NULL 
           AND DATE_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- Major complication proxy: AKI or sepsis (ICD-9/10)
    MAX(CASE 
      WHEN di.icd_code LIKE 'N17%' OR di.icd_code LIKE '584%' OR 
           di.icd_code LIKE 'A41%' OR di.icd_code LIKE '038%' THEN 1 
      ELSE 0 
    END) AS has_complication,
    -- Hospital LOS (days)
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
  GROUP BY 
    p.subject_id, p.anchor_age, p.anchor_year, a.hadm_id, a.admittime, 
    a.dischtime, a.deathtime, a.hospital_expire_flag, p.dod
),

cohort_raw AS (
  -- Add primary HF flag
  SELECT 
    af.*,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
        ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE d.subject_id = af.subject_id 
        AND d.hadm_id = af.hadm_id 
        AND d.seq_num = 1 
        AND icd.long_title LIKE '%heart failure%'
    ) THEN 1 ELSE 0 END AS has_hf_primary
  FROM all_females af
),

cohort AS (
  SELECT * FROM cohort_raw WHERE has_hf_primary = 1
),

cohort_quantiles AS (
  SELECT 
    APPROX_QUANTILES(risk_score_proxy, 4)[OFFSET(2)] AS median_risk,
    APPROX_QUANTILES(risk_score_proxy, 4)[OFFSET(1)] AS q1_risk,
    APPROX_QUANTILES(risk_score_proxy, 4)[OFFSET(3)] AS q3_risk
  FROM cohort
),

all_females_quantiles AS (
  SELECT 
    APPROX_QUANTILES(risk_score_proxy, 100) AS risk_quantiles
  FROM all_females
),

percentile_calc AS (
  SELECT 
    cq.median_risk,
    -- Linear interpolation for percentile
    CASE 
      WHEN cq.median_risk <= afq.risk_quantiles[OFFSET(0)] THEN 0
      WHEN cq.median_risk >= afq.risk_quantiles[OFFSET(99)] THEN 100
      ELSE 
        100.0 * (
          (cq.median_risk - afq.risk_quantiles[OFFSET(0)]) / 
          (afq.risk_quantiles[OFFSET(99)] - afq.risk_quantiles[OFFSET(0)])
        ) * (99.0 / 100.0)  -- Approximate position in 0-99 quantiles
    END AS risk_percentile
  FROM cohort_quantiles cq
  CROSS JOIN all_females_quantiles afq
)

-- Cohort metrics (survivors for LOS)
SELECT 
  'Cohort (HF + ICU)' AS group_type,
  pc.median_risk AS median_risk_score,
  cq.q1_risk AS iqr_risk_lower,
  cq.q3_risk AS iqr_risk_upper,
  AVG(c.mortality_30d) AS mortality_30d_rate,
  AVG(c.has_complication) AS complication_rate,
  AVG(CASE WHEN c.hospital_expire_flag = 0 THEN c.los_days ELSE NULL END) AS avg_los_survivors,
  pc.risk_percentile
FROM cohort c
CROSS JOIN cohort_quantiles cq
CROSS JOIN percentile_calc pc

UNION ALL

-- All females reference (median risk only)
SELECT 
  'All Females 43-53 (ICU)' AS group_type,
  APPROX_QUANTILES(risk_score_proxy, 4)[OFFSET(2)] AS median_risk_score,
  NULL AS iqr_risk_lower,
  NULL AS iqr_risk_upper,
  NULL AS mortality_30d_rate,
  NULL AS complication_rate,
  NULL AS avg_los_survivors,
  NULL AS risk_percentile
FROM all_females;