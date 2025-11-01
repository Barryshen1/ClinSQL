WITH 
-- Step 1: Identify patients with pulmonary embolism
pe_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'I26%'
),

-- Step 2: Calculate Elixhauser Comorbidity Index
elixhauser_scores AS (
  SELECT hadm_id, COUNT(DISTINCT comorbidity) AS elixhauser_score
  FROM (
    SELECT hadm_id, CASE
      WHEN icd_code LIKE 'A%' THEN 'AIDS'
      -- Simplified example; actual implementation requires a comprehensive mapping
      ELSE 'Other'
    END AS comorbidity
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
  ) 
  GROUP BY hadm_id
),

-- Step 3: Filter patients based on criteria
filtered_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, 
         es.elixhauser_score, 
         CASE WHEN p.dod <= DATE_ADD(a.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_within_90_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN pe_patients pe ON a.hadm_id = pe.hadm_id
  JOIN elixhauser_scores es ON a.hadm_id = es.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 81 AND 91
),

-- Step 4: Calculate mean risk score and 90-day mortality
elixhauser_percentile AS (
  SELECT PERCENTILE_CONT(elixhauser_score, 0.75) AS elixhauser_75th_percentile
  FROM filtered_patients
),

summary_stats AS (
  SELECT 
    AVG(elixhauser_score) AS mean_elixhauser_score,
    AVG(died_within_90_days) AS mortality_90_days
  FROM filtered_patients
),

-- Step 5: Compare AKI/ARDS rates and LOS among survivors
survivors AS (
  SELECT hadm_id, admittime, dischtime, elixhauser_score
  FROM filtered_patients
  WHERE died_within_90_days = 0
),

aki_ards_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9')  -- AKI ICD-10 codes
     OR icd_code LIKE 'J80%'  -- ARDS ICD-10 code
),

los_comparison AS (
  SELECT 
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los_survivors,
    AVG(CASE WHEN s.hadm_id IN (SELECT hadm_id FROM aki_ards_patients) THEN 1 ELSE 0 END) AS aki_ards_rate_survivors
  FROM survivors s
)

SELECT 
  (SELECT mean_elixhauser_score FROM summary_stats) AS mean_risk_score,
  (SELECT mortality_90_days FROM summary_stats) AS mortality_90_days,
  (SELECT elixhauser_75th_percentile FROM elixhauser_percentile) AS elixhauser_75th_percentile,
  (SELECT mean_los_survivors FROM los_comparison) AS mean_los_survivors,
  (SELECT aki_ards_rate_survivors FROM los_comparison) AS aki_ards_rate_survivors;