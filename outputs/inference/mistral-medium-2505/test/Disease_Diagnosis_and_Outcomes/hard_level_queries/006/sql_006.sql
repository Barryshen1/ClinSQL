WITH
-- Define lower GI bleeding ICD codes
lower_gi_bleeding_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('K922', 'K921', 'K920', 'K9281', 'K9289')  -- Example codes, adjust as needed
),

-- Get female patients aged 70-80 with lower GI bleeding
base_population AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN lower_gi_bleeding_codes lgib ON d.icd_code = lgib.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type NOT LIKE '%NEWBORN%'
),

-- Calculate a simplified composite risk score (example components)
risk_score_components AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    bp.admittime,
    bp.dischtime,
    -- Comorbidity count (simplified)
    COUNT(DISTINCT CASE WHEN d.icd_code IN ('E119', 'I10', 'I509') THEN d.icd_code END) AS comorbidity_count,
    -- Low hemoglobin (example lab)
    MAX(CASE WHEN le.itemid = 50821 THEN le.valuenum ELSE NULL END) AS min_hemoglobin,
    -- High heart rate (example vital)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS max_heart_rate
  FROM base_population bp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON bp.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON bp.hadm_id = le.hadm_id AND le.itemid = 50821
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON bp.hadm_id = ce.hadm_id AND ce.itemid = 220045
  GROUP BY bp.subject_id, bp.hadm_id, bp.admittime, bp.dischtime
),

-- Calculate the composite risk score (simplified example)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Example scoring formula (adjust weights as needed)
    (comorbidity_count * 2) +
    (CASE WHEN min_hemoglobin < 10 THEN 3 ELSE 0 END) +
    (CASE WHEN max_heart_rate > 100 THEN 2 ELSE 0 END) AS composite_risk_score
  FROM risk_score_components
),

-- Assign quintiles based on risk score
quintiles AS (
  SELECT
    r.*,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM risk_scores r
),

-- Calculate outcomes
outcomes AS (
  SELECT
    q.risk_quintile,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    p.dod,
    -- 90-day mortality
    CASE WHEN DATE_DIFF(DATE(p.dod), DATE(q.admittime), DAY) <= 90 THEN 1 ELSE 0 END AS is_death_90day,
    -- Major complications (example: sepsis or acute kidney injury)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = q.hadm_id
      AND d.icd_code IN ('A419', 'N179')  -- Example complication codes
    ) THEN 1 ELSE 0 END AS has_major_complication,
    -- LOS for 90-day survivors
    CASE WHEN DATE_DIFF(DATE(p.dod), DATE(q.admittime), DAY) > 90 OR p.dod IS NULL
         THEN TIMESTAMP_DIFF(q.dischtime, q.admittime, HOUR)/24
         ELSE NULL END AS los_survivors
  FROM quintiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON q.subject_id = p.subject_id
),

-- Aggregate results by quintile
quintile_aggregates AS (
  SELECT
    risk_quintile,
    COUNT(DISTINCT hadm_id) AS n,
    SUM(is_death_90day) AS deaths_90day,
    SUM(has_major_complication) AS major_complications,
    APPROX_QUANTILES(los_survivors, 100)[OFFSET(50)] AS median_los_survivors
  FROM outcomes
  GROUP BY risk_quintile
)

-- Final results
SELECT
  risk_quintile,
  n,
  ROUND(SUM(deaths_90day) / n * 100, 2) AS mortality_rate_90day_pct,
  ROUND(SUM(major_complications) / n * 100, 2) AS major_complication_rate_pct,
  ROUND(median_los_survivors, 2) AS median_los_survivors_days
FROM quintile_aggregates
GROUP BY risk_quintile, n, median_los_survivors
ORDER BY risk_quintile;