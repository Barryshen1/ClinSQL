WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 62 AND 72
),
temperature_data AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ep.intime,
    CASE 
      WHEN ce.itemid = 682 THEN (ce.valuenum - 32) * 5.0/9
      ELSE ce.valuenum
    END AS temperature_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN eligible_patients ep 
    ON ce.subject_id = ep.subject_id 
    AND ce.hadm_id = ep.hadm_id 
    AND ce.stay_id = ep.stay_id
  WHERE ce.itemid IN (223761, 676, 678, 682, 223835)
    AND ce.valuenum IS NOT NULL
),
temperature_categories AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    temperature_c,
    intime,
    CASE 
      WHEN temperature_c < 36.0 THEN 'Hypothermia'
      WHEN temperature_c BETWEEN 36.0 AND 37.9 THEN 'Normal'
      WHEN temperature_c >= 38.0 THEN 'Hyperthermia'
    END AS temp_category
  FROM temperature_data
  WHERE charttime BETWEEN intime AND intime + INTERVAL 24 HOUR
),
aki_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('N17.0', 'N17.1', 'N17.8', 'N17.9')
    AND icd_version = 10
),
category_measurements AS (
  SELECT 
    temp_category,
    temperature_c,
    subject_id,
    hadm_id
  FROM temperature_categories
),
category_stats AS (
  SELECT 
    temp_category,
    COUNT(*) AS measurement_count,
    AVG(temperature_c) AS mean_temp,
    APPROX_QUANTILES(temperature_c, 100)[OFFSET(50)] AS median_temp,
    APPROX_QUANTILES(temperature_c, 100)[SAFE_OFFSET(25)] AS q1_temp,
    APPROX_QUANTILES(temperature_c, 100)[SAFE_OFFSET(75)] AS q3_temp,
    COUNT(DISTINCT subject_id) AS patient_count_in_category
  FROM category_measurements
  GROUP BY temp_category
),
aki_in_category AS (
  SELECT 
    cm.temp_category,
    COUNT(DISTINCT aki.subject_id) AS aki_patient_count
  FROM category_measurements cm
  JOIN aki_patients aki 
    ON cm.subject_id = aki.subject_id 
    AND cm.hadm_id = aki.hadm_id
  GROUP BY cm.temp_category
)
SELECT 
  cs.temp_category,
  cs.measurement_count,
  cs.mean_temp,
  cs.median_temp,
  cs.q1_temp,
  cs.q3_temp,
  cs.q3_temp - cs.q1_temp AS iqr_temp,
  IFNULL(aki.aki_patient_count, 0) * 1.0 / cs.patient_count_in_category AS aki_rate
FROM category_stats cs
LEFT JOIN aki_in_category aki 
  ON cs.temp_category = aki.temp_category
ORDER BY 
  CASE temp_category 
    WHEN 'Hypothermia' THEN 1 
    WHEN 'Normal' THEN 2 
    WHEN 'Hyperthermia' THEN 3 
  END;