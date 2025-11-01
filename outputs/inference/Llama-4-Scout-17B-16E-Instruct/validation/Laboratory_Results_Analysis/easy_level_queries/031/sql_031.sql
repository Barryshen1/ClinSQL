WITH 
-- Identify male patients who had an ICU stay
male_icustay_patients AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    ic.stay_id,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
  ON 
    a.hadm_id = ic.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
),

-- Identify serum potassium measurements
serum_potassium_measurements AS (
  SELECT 
    subject_id, 
    hadm_id, 
    charttime, 
    valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 220050  -- Serum potassium
    AND valuenum IS NOT NULL
),

-- Find discharge day measurements
discharge_day_measurements AS (
  SELECT 
    mip.subject_id, 
    mip.hadm_id, 
    sp.valuenum
  FROM 
    male_icustay_patients mip
  INNER JOIN 
    serum_potassium_measurements sp 
  ON 
    mip.subject_id = sp.subject_id 
    AND mip.hadm_id = sp.hadm_id
  WHERE 
    sp.charttime BETWEEN TIMESTAMP_SUB(mip.dischtime, INTERVAL 1 DAY) AND mip.dischtime
)

-- Calculate 75th percentile
SELECT 
  APPROX_QUANTILES(valuenum, 75) AS percentile_75
FROM 
  discharge_day_measurements;