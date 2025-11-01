WITH
-- Get female patients aged 89-99
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 89 AND 99
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get temperature measurements with item details
temperature_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    di.unitname,
    CASE
      WHEN di.unitname = 'F' THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
      ELSE ce.valuenum
    END AS temp_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  WHERE
    ce.itemid IN (223761, 223762)  -- Temperature itemids
    AND ce.valuenum IS NOT NULL
),

-- Categorize temperatures
temp_categories AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    temp_celsius,
    CASE
      WHEN temp_celsius < 36 THEN '<36'
      WHEN temp_celsius BETWEEN 36 AND 37.9 THEN '36-37.9'
      WHEN temp_celsius >= 38 THEN '>=38'
      ELSE NULL
    END AS temp_category
  FROM
    temperature_measurements
  WHERE
    temp_celsius IS NOT NULL
),

-- Get MI diagnoses for these patients
mi_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      d.icd_code LIKE '410%'  -- ICD-9 for acute MI
      OR d.icd_code LIKE 'I21%'  -- ICD-10 for acute MI
    )
),

-- Count MI cases per patient
mi_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT hadm_id) AS mi_count
  FROM
    mi_diagnoses
  GROUP BY
    subject_id
),

-- Final aggregation
final_stats AS (
  SELECT
    temp_category,
    COUNT(DISTINCT subject_id) AS unique_patient_count,
    COUNT(*) AS measurement_count,
    AVG(temp_celsius) AS mean_temp,
    APPROX_QUANTILES(temp_celsius, 100)[OFFSET(50)] AS median_temp,
    APPROX_QUANTILES(temp_celsius, 100)[OFFSET(25)] AS q1_temp,
    APPROX_QUANTILES(temp_celsius, 100)[OFFSET(75)] AS q3_temp,
    (APPROX_QUANTILES(temp_celsius, 100)[OFFSET(75)] - APPROX_QUANTILES(temp_celsius, 100)[OFFSET(25)]) AS iqr_temp,
    SUM(CASE WHEN subject_id IN (SELECT subject_id FROM mi_counts) THEN 1 ELSE 0 END) AS mi_patient_count,
    COUNT(DISTINCT subject_id) AS total_patient_count,
    ROUND(SUM(CASE WHEN subject_id IN (SELECT subject_id FROM mi_counts) THEN 1 ELSE 0 END) /
          COUNT(DISTINCT subject_id), 4) AS mi_rate
  FROM
    temp_categories
  GROUP BY
    temp_category
)

SELECT
  temp_category,
  unique_patient_count,
  measurement_count,
  ROUND(mean_temp, 2) AS mean_temp,
  ROUND(median_temp, 2) AS median_temp,
  ROUND(q1_temp, 2) AS q1_temp,
  ROUND(q3_temp, 2) AS q3_temp,
  ROUND(iqr_temp, 2) AS iqr_temp,
  mi_patient_count,
  total_patient_count,
  ROUND(mi_rate, 4) AS mi_rate
FROM
  final_stats
ORDER BY
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    WHEN '>=38' THEN 3
    ELSE 4
  END;