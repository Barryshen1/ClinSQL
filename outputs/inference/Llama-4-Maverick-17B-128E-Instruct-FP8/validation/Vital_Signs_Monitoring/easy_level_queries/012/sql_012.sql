WITH 
-- Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 49 AND 59
),

-- Identify diastolic BP itemid
diastolic_bp_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Diastolic Blood Pressure%' AND linksto = 'chartevents'
),

-- Get ICU stays in step-down/IMC for eligible patients
eligible_stays AS (
  SELECT i.stay_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients p ON i.subject_id = p.subject_id
  WHERE i.first_careunit = 'Step-Down Unit' OR i.first_careunit LIKE '%IMC%' 
),

-- Calculate mean diastolic BP per stay
mean_diastolic_bp AS (
  SELECT e.stay_id, AVG(c.valuenum) AS mean_dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN eligible_stays e ON c.stay_id = e.stay_id
  INNER JOIN diastolic_bp_itemid d ON c.itemid = d.itemid
  WHERE c.valuenum IS NOT NULL
  GROUP BY e.stay_id
)

-- Calculate IQR of mean diastolic BP
SELECT 
  APPROX_QUANTILES(mean_dbp, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(mean_dbp, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(mean_dbp, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(mean_dbp, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_dbp, 100)[OFFSET(25)] AS iqr
FROM mean_diastolic_bp;