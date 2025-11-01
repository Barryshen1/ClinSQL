WITH
-- Get male patients aged 71-81
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 71 AND 81
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.first_careunit,
    s.last_careunit,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients p ON s.subject_id = p.subject_id
),

-- Get temperature measurements (first 48 hours)
temp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) AS hours_since_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays i ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label LIKE '%Temperature%'
    AND TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) <= 48
    AND ce.valuenum IS NOT NULL
),

-- Calculate average temperature per stay (first 48h)
avg_temp_per_stay AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(
      CASE
        WHEN valueuom = 'F' THEN (valuenum - 32) * 5/9  -- Convert Fahrenheit to Celsius
        ELSE valuenum
      END
    ) AS avg_temp_celsius,
    COUNT(*) AS temp_measurements_count
  FROM
    temp_measurements
  GROUP BY
    stay_id, subject_id, hadm_id
  HAVING
    temp_measurements_count > 0
),

-- Categorize temperatures
temp_categories AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    avg_temp_celsius,
    CASE
      WHEN avg_temp_celsius < 36.0 THEN '<36.0'
      WHEN avg_temp_celsius BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN avg_temp_celsius >= 38.0 THEN '>=38.0'
      ELSE NULL
    END AS temp_category
  FROM
    avg_temp_per_stay
),

-- Get MI diagnoses
mi_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410%') OR  -- ICD-9 MI codes
    (d.icd_version = 10 AND d.icd_code LIKE 'I21%')   -- ICD-10 MI codes
),

-- Flag stays with MI
stays_with_mi AS (
  SELECT
    t.stay_id,
    t.subject_id,
    t.hadm_id,
    t.temp_category,
    t.avg_temp_celsius,
    CASE WHEN m.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM
    temp_categories t
  LEFT JOIN
    mi_diagnoses m ON t.subject_id = m.subject_id AND t.hadm_id = m.hadm_id
),

-- Calculate percentiles per category
temp_stats AS (
  SELECT DISTINCT
    temp_category,
    PERCENTILE_CONT(avg_temp_celsius, 0.5) OVER (PARTITION BY temp_category) AS median_temp,
    PERCENTILE_CONT(avg_temp_celsius, 0.25) OVER (PARTITION BY temp_category) AS q1_temp,
    PERCENTILE_CONT(avg_temp_celsius, 0.75) OVER (PARTITION BY temp_category) AS q3_temp
  FROM
    stays_with_mi
)

-- Final aggregation
SELECT
  s.temp_category,
  COUNT(DISTINCT s.stay_id) AS stay_count,
  AVG(s.avg_temp_celsius) AS mean_temp,
  MAX(t.median_temp) AS median_temp,
  MAX(t.q1_temp) AS q1_temp,
  MAX(t.q3_temp) AS q3_temp,
  MAX(t.q3_temp) - MAX(t.q1_temp) AS iqr_temp,
  SUM(s.has_mi) AS mi_count,
  SUM(s.has_mi) / COUNT(DISTINCT s.stay_id) AS mi_rate
FROM
  stays_with_mi s
JOIN
  temp_stats t ON s.temp_category = t.temp_category
GROUP BY
  s.temp_category
ORDER BY
  s.temp_category;