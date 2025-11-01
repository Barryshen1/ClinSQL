WITH
-- Get female patients aged 90-100
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 90 AND 100
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

-- Get SpO2 measurements in first 24 hours of each stay
spo2_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'SpO2'
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate average SpO2 per stay (first 24 hours)
avg_spo2_per_stay AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(spo2_value) AS avg_spo2
  FROM
    spo2_measurements
  GROUP BY
    stay_id, subject_id, hadm_id
),

-- Categorize SpO2 into bins and keep avg_spo2
spo2_categories AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    avg_spo2,
    CASE
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN avg_spo2 > 95 THEN '>95'
      ELSE NULL
    END AS spo2_category
  FROM
    avg_spo2_per_stay
),

-- Get creatinine measurements for AKI calculation
creatinine_measurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
),

-- Calculate baseline creatinine (minimum value in first 7 days)
baseline_creatinine AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(creatinine_value) AS baseline_creatinine
  FROM
    creatinine_measurements cm
  JOIN
    icu_stays s ON cm.subject_id = s.subject_id AND cm.hadm_id = s.hadm_id
  WHERE
    cm.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 7 DAY)
  GROUP BY
    subject_id, hadm_id
),

-- Calculate peak creatinine (maximum value in first 7 days)
peak_creatinine AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(creatinine_value) AS peak_creatinine
  FROM
    creatinine_measurements cm
  JOIN
    icu_stays s ON cm.subject_id = s.subject_id AND cm.hadm_id = s.hadm_id
  WHERE
    cm.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 7 DAY)
  GROUP BY
    subject_id, hadm_id
),

-- Identify AKI based on KDIGO criteria (increase of ≥0.3 mg/dL or ≥1.5x baseline)
aki_identification AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    CASE
      WHEN (p.peak_creatinine - b.baseline_creatinine) >= 0.3
        OR (p.peak_creatinine / NULLIF(b.baseline_creatinine, 0)) >= 1.5
      THEN 1
      ELSE 0
    END AS has_aki
  FROM
    peak_creatinine p
  JOIN
    baseline_creatinine b ON p.subject_id = b.subject_id AND p.hadm_id = b.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    spo2_category,
    COUNT(DISTINCT stay_id) AS n,
    ROUND(AVG(avg_spo2), 2) AS mean_spo2,
    ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)], 2) AS median_spo2,
    ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)], 2) AS q1_spo2,
    ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)], 2) AS q3_spo2,
    ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] -
          APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)], 2) AS iqr_spo2,
    SUM(has_aki) AS aki_count,
    ROUND(SAFE_DIVIDE(SUM(has_aki), COUNT(DISTINCT stay_id)) * 100, 2) AS aki_rate_percentage
  FROM
    spo2_categories sc
  LEFT JOIN
    aki_identification a ON sc.subject_id = a.subject_id AND sc.hadm_id = a.hadm_id
  GROUP BY
    spo2_category
)

-- Final output
SELECT
  spo2_category,
  n,
  mean_spo2,
  median_spo2,
  q1_spo2,
  q3_spo2,
  iqr_spo2,
  aki_rate_percentage
FROM
  final_data
ORDER BY
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;