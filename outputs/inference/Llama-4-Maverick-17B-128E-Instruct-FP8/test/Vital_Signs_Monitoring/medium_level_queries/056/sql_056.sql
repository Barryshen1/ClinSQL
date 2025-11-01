WITH 
-- Step 1: Identify temperature itemid
temp_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Temperature%' AND param_type = 'Numeric'
),

-- Step 2: Filter patients and get their ICU stays
icu_patients AS (
  SELECT p.subject_id, ie.stay_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 89 AND 99
),

-- Step 3: Get temperature measurements for these patients
temp_measurements AS (
  SELECT ip.subject_id, ce.valuenum, 
         CASE 
           WHEN ce.valuenum < 36 THEN '<36'
           WHEN ce.valuenum BETWEEN 36 AND 37.9 THEN '36-37.9'
           ELSE '>=38'
         END AS temp_category
  FROM icu_patients ip
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ip.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM temp_itemid) AND ce.valuenum IS NOT NULL
),

-- Step 4: Calculate statistics for temperature categories
stats AS (
  SELECT temp_category, 
         COUNT(*) AS measurement_count,
         COUNT(DISTINCT subject_id) AS patient_count,
         AVG(valuenum) AS mean_temp,
         APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_temp,
         APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1_temp,
         APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3_temp
  FROM temp_measurements
  GROUP BY temp_category
),

-- Step 5: Calculate MI rate (simplified example, actual implementation depends on how MI is defined)
mi_rate AS (
  SELECT COUNT(DISTINCT p.subject_id) AS mi_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON di.subject_id = p.subject_id
  WHERE di.icd_code LIKE 'I21%' AND p.gender = 'F' AND p.anchor_age BETWEEN 89 AND 99
)

-- Final query
SELECT 
  s.temp_category,
  s.measurement_count,
  s.patient_count,
  s.mean_temp,
  s.median_temp,
  s.q3_temp - s.q1_temp AS iqr_temp,
  (SELECT mi_count FROM mi_rate) / (SELECT COUNT(DISTINCT subject_id) FROM icu_patients) AS mi_rate
FROM stats s
ORDER BY s.temp_category;