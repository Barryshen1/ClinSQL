WITH temperature_data AS (
  SELECT 
    ce.subject_id,
    ce.valuenum AS temp_value
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ce.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  WHERE di.label = 'Temperature'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 43  -- Physiological range, reduce outliers
),
temperature_categories AS (
  SELECT
    subject_id,
    temp_value,
    CASE
      WHEN temp_value < 36 THEN '<36'
      WHEN temp_value >= 36 AND temp_value < 38 THEN '36-37.9'
      WHEN temp_value >= 38 THEN '>=38'
    END AS temp_category
  FROM temperature_data
),
mi_diagnoses AS (
  SELECT DISTINCT
    di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = '410' OR d.icd_code = '412')
),
category_stats AS (
  SELECT
    tc.temp_category,
    tc.subject_id,
    tc.temp_value,
    CASE WHEN mi.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM temperature_categories tc
  LEFT JOIN mi_diagnoses mi
    ON tc.subject_id = mi.subject_id
),
aggregated AS (
  SELECT
    temp_category,
    AVG(temp_value) AS mean_temperature,
    APPROX_QUANTILES(temp_value, 100)[OFFSET(50)] AS median_temperature,
    APPROX_QUANTILES(temp_value, 100)[OFFSET(25)] AS iqr_lower,
    APPROX_QUANTILES(temp_value, 100)[OFFSET(75)] AS iqr_upper,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(*) AS total_measurements,
    SUM(has_mi) AS mi_patients
  FROM category_stats
  GROUP BY temp_category
)
SELECT
  temp_category,
  ROUND(mean_temperature, 2) AS mean_temperature,
  ROUND(median_temperature, 2) AS median_temperature,
  CONCAT(ROUND(iqr_lower, 2), ' - ', ROUND(iqr_upper, 2)) AS iqr_temperature,
  unique_patients,
  total_measurements,
  ROUND(SAFE_DIVIDE(mi_patients, unique_patients), 3) AS mi_rate
FROM aggregated
ORDER BY temp_category;