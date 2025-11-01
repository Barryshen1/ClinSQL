WITH 
-- Filter patients and get ICU stay information
icu_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender, 
    ic.stay_id, 
    ic.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
  ON 
    p.subject_id = ic.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 85 AND 95
),

-- Get blood pressure measurements
bp_measurements AS (
  SELECT 
    icp.subject_id, 
    icp.stay_id, 
    ce.charttime, 
    ce.itemid, 
    ce.valuenum
  FROM 
    icu_patients icp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
  ON 
    icp.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220050, 220179)  -- systolic and diastolic blood pressure
    AND ce.charttime BETWEEN icp.intime AND TIMESTAMP_ADD(icp.intime, INTERVAL 1 DAY)
),

-- Calculate MAP
map_values AS (
  SELECT 
    subject_id, 
    stay_id, 
    charttime,
    (2 * diastolic + systolic) / 3 AS map_value
  FROM 
  (
    SELECT 
      subject_id, 
      stay_id, 
      charttime,
      MAX(CASE WHEN itemid = 220050 THEN valuenum END) AS systolic,
      MAX(CASE WHEN itemid = 220179 THEN valuenum END) AS diastolic
    FROM 
      bp_measurements
    GROUP BY 
      subject_id, 
      stay_id, 
      charttime
  ) t
)

-- Calculate mean MAP and standard deviation
SELECT 
  STDDEV(map_value) AS std_dev_map
FROM 
  map_values
WHERE 
  map_value > 0;