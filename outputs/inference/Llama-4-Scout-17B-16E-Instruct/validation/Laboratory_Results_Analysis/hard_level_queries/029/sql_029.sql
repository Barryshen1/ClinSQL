WITH 
-- Target population: female inpatients aged 50-60 with HHS
target_population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_code LIKE '%276.51%'  -- Hyperosmolar hyperglycemic state
),

-- Laboratory instability score (simple example: count abnormal lab results within 48h)
lab_instability_score AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON le.hadm_id = a.hadm_id
  WHERE 
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY 
    le.hadm_id
),

-- Calculate 75th percentile of lab instability score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(score, 0.75)[OFFSET(0)] AS threshold
  FROM 
    lab_instability_score
),

-- Admissions with score >= threshold
high_risk_admissions AS (
  SELECT 
    lis.hadm_id,
    a.dischtime,
    a.deathtime,
    COALESCE(a.deathtime, a.dischtime) AS outcome_time,
    a.admittime  -- Include admittime for calculations
  FROM 
    lab_instability_score lis
  JOIN 
    target_population tp 
      ON lis.hadm_id = tp.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON lis.hadm_id = a.hadm_id
  CROSS JOIN 
    percentile_score ps
  WHERE 
    lis.score >= ps.threshold
),

-- Calculate mortality, mean LOS, and critical-lab rates
results AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS num_admissions,
    SUM(CASE WHEN outcome_time = deathtime THEN 1 ELSE 0 END) AS num_deaths,
    AVG(TIMESTAMP_DIFF(outcome_time, admittime, DAY)) AS mean_LOS
  FROM 
    high_risk_admissions
)

SELECT 
  num_admissions,
  num_deaths,
  num_deaths / num_admissions AS mortality_rate,
  mean_LOS
FROM 
  results;