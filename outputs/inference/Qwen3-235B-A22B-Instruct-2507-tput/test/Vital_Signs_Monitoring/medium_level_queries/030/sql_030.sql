WITH temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%temperature%'
    AND LOWER(unitname) = 'celsius'
),
first_24h_temps AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_temp_24h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN temperature_items ti ON ce.itemid = ti.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30.0 AND 43.0
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY ce.stay_id
),
mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'I21%' AND di.icd_version = 10)
     OR (d.icd_code IN ('410') AND di.icd_version = 9) -- ICD-9 for MI
),
patient_stays AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    p.anchor_age,
    p.gender,
    f.mean_temp_24h,
    CASE 
      WHEN f.mean_temp_24h < 36.0 THEN '<36.0'
      WHEN f.mean_temp_24h >= 36.0 AND f.mean_temp_24h < 38.0 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS temp_category
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON icu.subject_id = p.subject_id
  INNER JOIN first_24h_temps f ON icu.stay_id = f.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
stay_with_mi AS (
  SELECT 
    ps.*,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_mi
  FROM patient_stays ps
  LEFT JOIN mi_diagnoses mi ON ps.hadm_id = mi.hadm_id
),
summary_stats AS (
  SELECT
    temp_category,
    COUNT(*) AS N,
    AVG(mean_temp_24h) AS mean_temp,
    APPROX_QUANTILES(mean_temp_24h, 1000)[OFFSET(500)] AS median_temp,
    APPROX_QUANTILES(mean_temp_24h, 1000)[OFFSET(750)] - APPROX_QUANTILES(mean_temp_24h, 1000)[OFFSET(250)] AS iqr_temp,
    SUM(had_mi) AS mi_count
  FROM stay_with_mi
  GROUP BY temp_category
)
SELECT
  temp_category,
  N,
  ROUND(mean_temp, 2) AS mean,
  ROUND(median_temp, 2) AS median,
  ROUND(iqr_temp, 2) AS iqr,
  ROUND(100.0 * mi_count / N, 2) AS mi_rate_percent
FROM summary_stats
ORDER BY temp_category;