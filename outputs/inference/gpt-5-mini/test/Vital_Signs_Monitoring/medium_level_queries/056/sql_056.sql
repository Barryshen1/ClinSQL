WITH mi_hadm AS (
  -- Admissions with myocardial infarction diagnoses (ICD9: 410*, ICD10: I21*/I22*)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND STARTS_WITH(icd_code, '410'))
     OR (icd_version = 10 AND (STARTS_WITH(icd_code, 'I21') OR STARTS_WITH(icd_code, 'I22')))
),

temp_items AS (
  -- Identify itemids that are temperature measurements by label/abbreviation
  SELECT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%'
     OR LOWER(label) LIKE '%temperature%'
     OR LOWER(IFNULL(abbreviation, '')) LIKE '%temp%'
),

temps AS (
  -- ICU temperature measurements for female patients aged 89-99
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    di.label AS item_label,
    ce.valuenum,
    CASE
      WHEN ce.valuenum < 36 THEN '<36'
      WHEN ce.valuenum < 38 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category,
    -- mark whether the admission has an MI diagnosis
    CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mi_flag
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  JOIN temp_items di
    ON ce.itemid = di.itemid
  LEFT JOIN mi_hadm m
    ON ce.hadm_id = m.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND ce.valuenum IS NOT NULL
    -- restrict to plausible body temperature range (Celsius)
    AND ce.valuenum BETWEEN 30 AND 45
)

SELECT
  temp_category AS temperature_category,
  COUNT(*) AS measurement_count,
  COUNT(DISTINCT subject_id) AS unique_patient_count,
  ROUND(AVG(valuenum), 2) AS mean_temperature,
  -- approximate percentiles using 101 quantiles (0..100). Offsets: 25 -> 25th, 50 -> median, 75 -> 75th
  (APPROX_QUANTILES(valuenum, 101))[OFFSET(25)] AS q1_temperature,
  (APPROX_QUANTILES(valuenum, 101))[OFFSET(50)] AS median_temperature,
  (APPROX_QUANTILES(valuenum, 101))[OFFSET(75)] AS q3_temperature,
  ((APPROX_QUANTILES(valuenum, 101))[OFFSET(75)] - (APPROX_QUANTILES(valuenum, 101))[OFFSET(25)]) AS iqr_temperature,
  COUNT(DISTINCT IF(mi_flag = 1, subject_id, NULL)) AS mi_patient_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(mi_flag = 1, subject_id, NULL)),
    NULLIF(COUNT(DISTINCT subject_id), 0)
  ) AS mi_rate
FROM temps
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    WHEN '>=38' THEN 3
    ELSE 4
  END;