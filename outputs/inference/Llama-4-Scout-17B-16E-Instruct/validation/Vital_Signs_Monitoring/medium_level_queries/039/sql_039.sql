WITH 
-- Define MAP measurements in ICU
map_measurements AS (
  SELECT 
    ic.stay_id,
    ic.charttime,
    ic.valuenum AS map_value,
    icu.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ic
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON ic.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ic.itemid = di.itemid
  WHERE 
    di.label = 'Mean Arterial Pressure'
    AND ic.valuenum IS NOT NULL
    AND ic.charttime BETWEEN icu.intime AND icu.intime + INTERVAL 48 HOUR
),

-- Filter patients by age and gender
icu_patients AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ic.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 83 AND 93
    AND p.gender = 'M'
),

-- Join patients with MAP measurements
patient_map_measurements AS (
  SELECT 
    pm.stay_id,
    pm.map_value
  FROM 
    map_measurements pm
  INNER JOIN 
    icu_patients ip ON pm.stay_id = ip.stay_id
),

-- Calculate average MAP per stay
stay_avg_map AS (
  SELECT 
    stay_id, 
    AVG(map_value) AS avg_map
  FROM 
    patient_map_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(map_value) >= 3
),

-- Calculate quantiles of average MAP
quantiles AS (
  SELECT 
    APPROX_QUANTILES(avg_map, 100) AS quantiles
  FROM 
    stay_avg_map
)

-- Find percentile of a specific MAP value
SELECT 
  PERCENTILE_CONT(60 WITHIN GROUP (ORDER BY avg_map)) AS percentile_value
FROM 
  stay_avg_map;