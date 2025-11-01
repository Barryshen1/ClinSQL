WITH 
-- Identify target population: male inpatients aged 49-59 with ischemic stroke
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.icd_code LIKE 'I63%'  -- Ischemic stroke
),

-- Glucose levels for target population
glucose_levels AS (
  SELECT 
    hadm_id,
    subject_id,
    CAST(value AS FLOAT64) AS value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 220050  -- Glucose
    AND hadm_id IN (SELECT hadm_id FROM target_population)
    AND value IS NOT NULL
),

-- Calculate 75th percentile of glucose levels
percentile_glucose AS (
  SELECT 
    APPROX_QUANTILES(value, 100) AS percentiles
  FROM 
    glucose_levels
),

-- Extract 75th percentile
extracted_percentile AS (
  SELECT 
    percentiles[OFFSET(74)] AS percentile_glucose
  FROM 
    percentile_glucose
),

-- Final query to identify target population and some outcomes
outcomes AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    tp.anchor_age,
    tp.gender,
    -- LOS
    icu.stay_id,
    icu.los,
    -- Mortality
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    target_population tp
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON tp.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON tp.hadm_id = a.hadm_id
)

-- Combine results
SELECT 
  o.*,
  ep.percentile_glucose
FROM 
  outcomes o
  CROSS JOIN extracted_percentile ep;