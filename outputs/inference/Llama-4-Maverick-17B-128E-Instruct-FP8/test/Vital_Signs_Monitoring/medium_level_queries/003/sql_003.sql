WITH 
-- Step 1: Filter patients and icu stays
patient_filter AS (
  SELECT p.subject_id, p.gender, 
         p.anchor_age AS age_at_anchor,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 71 AND 81
),
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patient_filter p ON i.subject_id = p.subject_id
),

-- Step 2: Calculate average temperature over first 48h for each ICU stay
temp_avg AS (
  SELECT i.stay_id, AVG(c.valuenum) AS avg_temp
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.label LIKE '%Temperature%' 
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.stay_id
),

-- Step 3: Identify MI cases
mi_cases AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON h.hadm_id = i.hadm_id
  WHERE d.long_title LIKE '%Myocardial infarction%' 
    OR d.long_title LIKE '%MI%' 
),

-- Step 4: Combine data and categorize temperature
combined_data AS (
  SELECT t.stay_id, t.avg_temp,
         CASE 
           WHEN t.avg_temp < 36.0 THEN '<36.0'
           WHEN t.avg_temp >= 38.0 THEN '>=38.0'
           ELSE '36.0-37.9'
         END AS temp_category,
         CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mi_flag
  FROM temp_avg t
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON t.stay_id = i.stay_id
  LEFT JOIN mi_cases m ON i.hadm_id = m.hadm_id
)

-- Step 5: Report per-stay mean, median, IQR of average temperature and MI rate
SELECT 
  temp_category,
  COUNT(*) AS num_stays,
  AVG(avg_temp) AS mean_avg_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(50)] AS median_avg_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(25)] AS q1_avg_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(75)] AS q3_avg_temp,
  AVG(mi_flag) AS mi_rate
FROM combined_data
GROUP BY temp_category
ORDER BY temp_category;