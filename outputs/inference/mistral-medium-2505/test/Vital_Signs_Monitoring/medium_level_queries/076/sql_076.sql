WITH
-- Get female patients aged 48-58
female_patients_48_58 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 48 AND 58
),

-- Get their ICU stays
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
    female_patients_48_58 p ON s.subject_id = p.subject_id
),

-- Calculate average HR in first 48 hours per stay
hr_data AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.stay_id = s.stay_id
  WHERE
    ce.itemid = 220045  -- Heart Rate
    AND ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

-- Categorize HR
hr_categories AS (
  SELECT
    stay_id,
    CASE
      WHEN avg_hr < 60 THEN '<60'
      WHEN avg_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN avg_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN avg_hr >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_category
  FROM
    hr_data
),

-- Count stays in each HR category
hr_distribution AS (
  SELECT
    hr_category,
    COUNT(stay_id) AS stay_count,
    ROUND(COUNT(stay_id) * 100.0 / SUM(COUNT(stay_id)) OVER(), 2) AS percentage
  FROM
    hr_categories
  WHERE
    hr_category IS NOT NULL
  GROUP BY
    hr_category
),

-- Identify AKI cases
aki_cases AS (
  SELECT DISTINCT
    s.stay_id
  FROM
    icu_stays s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON s.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for AKI
    (d.icd_version = 9 AND d.icd_code IN (
      '584.5', '584.6', '584.7', '584.8', '584.9',
      '586', '580.4', '580.81', '580.89', '580.9'
    ))
    OR
    -- ICD-10 codes for AKI (more specific)
    (d.icd_version = 10 AND d.icd_code LIKE 'N17.%')
),

-- Calculate AKI rate
aki_rate AS (
  SELECT
    COUNT(DISTINCT s.stay_id) AS total_stays,
    COUNT(DISTINCT a.stay_id) AS aki_stays,
    ROUND(COUNT(DISTINCT a.stay_id) * 100.0 / COUNT(DISTINCT s.stay_id), 2) AS aki_percentage
  FROM
    icu_stays s
  LEFT JOIN
    aki_cases a ON s.stay_id = a.stay_id
)

-- Final output
SELECT
  'HR Distribution' AS metric,
  hr_category,
  percentage
FROM
  hr_distribution

UNION ALL

SELECT
  'AKI Rate' AS metric,
  'AKI Percentage' AS hr_category,  -- Changed from category to hr_category
  aki_percentage AS percentage
FROM
  aki_rate
ORDER BY
  metric, hr_category;