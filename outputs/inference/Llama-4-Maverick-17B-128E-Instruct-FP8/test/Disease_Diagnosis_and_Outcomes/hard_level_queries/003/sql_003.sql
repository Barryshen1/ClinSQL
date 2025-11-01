WITH 
-- Step 1: Identify the cohort (females aged 70-80 with PE)
cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d_diag.long_title LIKE '%Pulmonary embolism%'
),

-- Step 2: Calculate comorbidity count as a proxy for risk score
comorbidity_count AS (
  SELECT diag.subject_id, diag.hadm_id, COUNT(DISTINCT diag.icd_code) as count_comorbidity
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN cohort ON diag.hadm_id = cohort.hadm_id
  GROUP BY diag.subject_id, diag.hadm_id
),

-- Step 3: Calculate risk score quintiles
risk_quintile AS (
  SELECT subject_id, hadm_id, count_comorbidity,
         NTILE(5) OVER (ORDER BY count_comorbidity) as risk_quintile
  FROM comorbidity_count
),

-- Step 4: Calculate outcomes (90-day mortality, AKI, ARDS, LOS)
outcomes AS (
  SELECT 
    r.hadm_id,
    r.risk_quintile,
    -- 90-day mortality
    CASE WHEN a.deathtime <= DATETIME_ADD(a.admittime, INTERVAL 90 DAY) OR p.dod <= DATETIME_ADD(a.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_90d,
    -- AKI (simplified using ICD codes)
    EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag WHERE diag.hadm_id = a.hadm_id AND diag.icd_code LIKE 'N17%') AS aki,
    -- ARDS (simplified using ICD codes)
    EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag WHERE diag.hadm_id = a.hadm_id AND diag.icd_code LIKE 'J80%') AS ards,
    -- LOS
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM risk_quintile r
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON r.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON r.subject_id = p.subject_id
),

-- Step 5: Aggregate outcomes by risk quintile
aggregated_outcomes AS (
  SELECT 
    risk_quintile,
    COUNT(CASE WHEN died_90d = 1 THEN 1 END) / COUNT(*) AS mortality_90d,
    COUNT(CASE WHEN aki THEN 1 END) / COUNT(*) AS aki_rate,
    COUNT(CASE WHEN ards THEN 1 END) / COUNT(*) AS ards_rate
  FROM outcomes
  GROUP BY risk_quintile
),

-- Calculate median LOS separately
median_los AS (
  SELECT DISTINCT risk_quintile,
         PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY risk_quintile) AS median_los
  FROM outcomes
),

-- Comparison cohort for general 90-day mortality
comparison_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.deathtime, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 70 AND 80
),
general_mortality AS (
  SELECT 
    COUNT(CASE WHEN (deathtime <= DATETIME_ADD(admittime, INTERVAL 90 DAY)) OR (dod <= DATETIME_ADD(admittime, INTERVAL 90 DAY)) THEN 1 END) / COUNT(*) AS general_mortality_90d
  FROM comparison_cohort
)

-- Final query
SELECT 
  ao.risk_quintile,
  ao.mortality_90d,
  gm.general_mortality_90d,
  ao.aki_rate,
  ao.ards_rate,
  ml.median_los
FROM aggregated_outcomes ao
INNER JOIN median_los ml ON ao.risk_quintile = ml.risk_quintile
CROSS JOIN general_mortality gm
ORDER BY ao.risk_quintile;