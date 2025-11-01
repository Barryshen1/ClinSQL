WITH
-- Define DVT ICD codes
dvt_icd_codes AS (
  SELECT icd_code
  FROM UNNEST([
    '453.4', '453.40', '453.41', '453.42', '453.8', '453.9',  -- ICD-9
    'I80.2', 'I80.3', 'I82.4', 'I82.5', 'I82.6', 'I82.8', 'I82.9'  -- ICD-10
  ]) AS icd_code
),

-- Get patients with DVT
dvt_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN dvt_icd_codes c ON d.icd_code = c.icd_code
),

-- Get male patients aged 71-81 with DVT
target_population AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    -- Calculate number of distinct diagnosis codes as comorbidity score
    (SELECT COUNT(DISTINCT icd_code) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN dvt_patients d ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- Calculate 90-day mortality
mortality_90day AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 90 THEN 1
      WHEN dod IS NOT NULL AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_within_90days
  FROM target_population
),

-- Calculate major complications (example: sepsis, hemorrhage, PE)
major_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code IN (
        '995.91', '995.92', '785.52',  -- ICD-9 for sepsis
        'R65.20', 'R65.21', 'R65.22',  -- ICD-10 for sepsis
        '459.0', '459.1', '459.2',     -- ICD-9 for hemorrhage
        'I60', 'I61', 'I62',            -- ICD-10 for hemorrhage
        '415.1', '415.11', '415.19',    -- ICD-9 for PE
        'I26.0', 'I26.9'                -- ICD-10 for PE
      ) THEN 1
      ELSE 0
    END AS has_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN target_population t ON d.subject_id = t.subject_id AND d.hadm_id = t.hadm_id
),

-- Calculate LOS for survivors
survivor_los AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM target_population
  WHERE deathtime IS NULL AND dod IS NULL
),

-- General inpatient population for comparison
general_inpatients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    (SELECT COUNT(DISTINCT icd_code) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- General inpatient complications
general_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code IN (
        '995.91', '995.92', '785.52',
        'R65.20', 'R65.21', 'R65.22',
        '459.0', '459.1', '459.2',
        'I60', 'I61', 'I62',
        '415.1', '415.11', '415.19',
        'I26.0', 'I26.9'
      ) THEN 1
      ELSE 0
    END AS has_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN general_inpatients g ON d.subject_id = g.subject_id AND d.hadm_id = g.hadm_id
),

-- General inpatient survivor LOS
general_survivor_los AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM general_inpatients
  WHERE deathtime IS NULL AND dod IS NULL
),

-- Calculate risk score statistics
risk_score_stats AS (
  SELECT
    PERCENTILE_CONT(comorbidity_score, 0.5) AS median_risk_score,
    PERCENTILE_CONT(comorbidity_score, 0.25) AS q1_risk_score,
    PERCENTILE_CONT(comorbidity_score, 0.75) AS q3_risk_score
  FROM target_population
),

-- Calculate mortality rate
mortality_rate AS (
  SELECT AVG(died_within_90days) AS mortality_90day_rate
  FROM mortality_90day
),

-- Calculate complication rates
complication_rates AS (
  SELECT
    AVG(has_major_complication) AS target_complication_rate,
    (SELECT AVG(has_major_complication) FROM general_complications) AS general_complication_rate
  FROM major_complications
),

-- Calculate LOS statistics
los_stats AS (
  SELECT
    PERCENTILE_CONT(los_days, 0.5) AS median_target_los,
    PERCENTILE_CONT(los_days, 0.25) AS q1_target_los,
    PERCENTILE_CONT(los_days, 0.75) AS q3_target_los,
    (SELECT PERCENTILE_CONT(los_days, 0.5) FROM general_survivor_los) AS median_general_los,
    (SELECT PERCENTILE_CONT(los_days, 0.25) FROM general_survivor_los) AS q1_general_los,
    (SELECT PERCENTILE_CONT(los_days, 0.75) FROM general_survivor_los) AS q3_general_los
  FROM survivor_los
),

-- Calculate risk percentile for a specific patient (assuming comorbidity_score = 5)
risk_percentile AS (
  SELECT
    PERCENT_RANK() OVER(ORDER BY comorbidity_score) AS percentile
  FROM target_population
  WHERE comorbidity_score = 5  -- Example value, replace with actual patient's score
  LIMIT 1
)

-- Final results
SELECT
  r.median_risk_score,
  r.q1_risk_score,
  r.q3_risk_score,
  m.mortality_90day_rate,
  c.target_complication_rate,
  c.general_complication_rate,
  l.median_target_los,
  l.q1_target_los,
  l.q3_target_los,
  l.median_general_los,
  l.q1_general_los,
  l.q3_general_los,
  p.percentile AS risk_percentile
FROM risk_score_stats r
CROSS JOIN mortality_rate m
CROSS JOIN complication_rates c
CROSS JOIN los_stats l
CROSS JOIN risk_percentile p;