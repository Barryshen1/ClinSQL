WITH temperature_measurements AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS temperature,
    CASE 
      WHEN ce.valuenum < 36 THEN '<36'
      WHEN ce.valuenum >= 36 AND ce.valuenum < 38 THEN '36-37.9'
      WHEN ce.valuenum >= 38 THEN '≥38'
    END AS temp_category
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON ce.subject_id = p.subject_id
  WHERE LOWER(di.label) LIKE '%temperature%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- exclude implausible values
),

mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    (di.icd_version = 9 AND di.icd_code LIKE '410%')
    OR 
    (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I23%'))
)

SELECT
  tm.temp_category,
  AVG(tm.temperature) AS mean_temperature,
  APPROX_QUANTILES(tm.temperature, 2)[OFFSET(1)] AS median_temperature,
  APPROX_QUANTILES(tm.temperature, 2)[OFFSET(2)] - APPROX_QUANTILES(tm.temperature, 2)[OFFSET(0)] AS iqr_temperature,
  COUNT(DISTINCT tm.subject_id) AS unique_patients,
  COUNT(*) AS measurement_count,
  SUM(CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(DISTINCT tm.subject_id) AS mi_rate
FROM temperature_measurements tm
LEFT JOIN mi_diagnoses mi
  ON tm.hadm_id = mi.hadm_id
GROUP BY tm.temp_category
ORDER BY tm.temp_category;