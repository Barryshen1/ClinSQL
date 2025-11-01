WITH 
-- Identify male patients aged 73-83 with pneumonia
target_population AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '481%'  -- pneumonia ICD-9 code
        OR icd_code LIKE 'J18%'  -- pneumonia ICD-10 code
    )
),

-- Calculate comorbidity burden
comorbidity_burden AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    subject_id, hadm_id
),

-- Determine top-quartile comorbidity threshold
comorbidity_threshold AS (
  SELECT 
    APPROX_QUANTILES(comorbidity_count, 0.75)[OFFSET(0)] AS threshold
  FROM 
    comorbidity_burden
),

-- Target patient
target_patient AS (
  SELECT 
    tp.subject_id,
    tp.anchor_age,
    tp.gender,
    tp.admittime,
    tp.hadm_id,
    tp.dischtime,
    tp.deathtime,
    cb.comorbidity_count
  FROM 
    target_population tp
  JOIN 
    comorbidity_burden cb
  ON 
    tp.subject_id = cb.subject_id AND tp.hadm_id = cb.hadm_id
  WHERE 
    tp.anchor_age = 78  -- target patient's age
    AND tp.gender = 'M'
),

-- Cohort outcomes
cohort_outcomes AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS cohort_size,
    SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS in_hospital_deaths,
    -- For simplicity, assuming major complications are those with a high-risk ICD code
    SUM(CASE WHEN di.icd_code LIKE '996%' THEN 1 ELSE 0 END) AS major_complications
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    tp.hadm_id = a.hadm_id
  JOIN 
    comorbidity_burden cb
  ON 
    tp.subject_id = cb.subject_id AND tp.hadm_id = cb.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    tp.hadm_id = di.hadm_id
  WHERE 
    cb.comorbidity_count >= (SELECT threshold FROM comorbidity_threshold)
)

-- Final results
SELECT 
  tp.subject_id,
  tp.anchor_age,
  tp.gender,
  tp.admittime,
  tp.hadm_id,
  tp.dischtime,
  tp.deathtime,
  tp.comorbidity_count,
  -- composite risk percentile (approximate)
  PERCENT_RANK() OVER (ORDER BY tp.comorbidity_count) AS risk_percentile,
  co.cohort_size,
  SAFE_DIVIDE(co.in_hospital_deaths, co.cohort_size) AS in_hospital_mortality_rate,
  SAFE_DIVIDE(co.major_complications, co.cohort_size) AS major_complication_rate,
  -- median survival days 
  APPROX_QUANTILES(
    DATE_DIFF(
      COALESCE(tp.deathtime, tp.dischtime), 
      tp.admittime
    ), 
    50
  )[OFFSET(0)] AS median_survival_days
FROM 
  target_patient tp
CROSS JOIN 
  cohort_outcomes co;