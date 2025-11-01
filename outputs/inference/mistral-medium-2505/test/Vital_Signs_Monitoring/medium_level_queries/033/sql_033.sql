WITH
-- Get male patients aged 62-72
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 62 AND 72
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
    male_patients p ON s.subject_id = p.subject_id
),

-- Get heart rate measurements (itemid 220045 is for Heart Rate)
heart_rates AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.stay_id = s.stay_id
  WHERE
    ce.itemid = 220045  -- Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude invalid values
),

-- Calculate mean heart rate per ICU stay
mean_heart_rates AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS mean_heart_rate
  FROM
    heart_rates
  GROUP BY
    stay_id
),

-- Categorize mean heart rates
heart_rate_categories AS (
  SELECT
    stay_id,
    CASE
      WHEN mean_heart_rate < 60 THEN '<60'
      WHEN mean_heart_rate BETWEEN 60 AND 99 THEN '60-99'
      WHEN mean_heart_rate BETWEEN 100 AND 119 THEN '100-119'
      WHEN mean_heart_rate >= 120 THEN '>=120'
      ELSE 'Unknown'
    END AS heart_rate_category
  FROM
    mean_heart_rates
),

-- Identify acute MI diagnoses (ICD-9: 410.xx, ICD-10: I21.xx)
acute_mi AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410.%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
),

-- Join heart rate categories with acute MI status
final_data AS (
  SELECT
    h.heart_rate_category,
    COUNT(DISTINCT h.stay_id) AS count_icu_stays,
    SUM(CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS count_with_acute_mi
  FROM
    heart_rate_categories h
  JOIN
    icu_stays s ON h.stay_id = s.stay_id
  LEFT JOIN
    acute_mi a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  GROUP BY
    h.heart_rate_category
)

-- Final output
SELECT
  heart_rate_category,
  count_icu_stays,
  ROUND(100 * count_with_acute_mi / count_icu_stays, 2) AS percent_with_acute_mi
FROM
  final_data
ORDER BY
  CASE heart_rate_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;