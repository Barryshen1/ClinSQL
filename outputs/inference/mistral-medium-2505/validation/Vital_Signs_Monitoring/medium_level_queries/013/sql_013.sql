WITH
-- Get male patients aged 51-61
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get their first ICU stays
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS row_num
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE
      intime IS NOT NULL
      AND outtime IS NOT NULL
  ) s
  JOIN
    male_patients p ON s.subject_id = p.subject_id
  WHERE
    s.row_num = 1
),

-- Get SpO2 measurements in first 48 hours
spo2_measurements AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    first_icu_stays s ON c.subject_id = s.subject_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220277  -- SpO2
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),

-- Calculate average SpO2 per stay
avg_spo2 AS (
  SELECT
    subject_id,
    stay_id,
    AVG(spo2_value) AS avg_spo2,
    COUNT(*) AS spo2_count
  FROM
    spo2_measurements
  GROUP BY
    subject_id, stay_id
  HAVING
    spo2_count >= 4  -- Require at least 4 measurements
),

-- Categorize SpO2
spo2_categories AS (
  SELECT
    subject_id,
    stay_id,
    CASE
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN avg_spo2 > 95 THEN '>95'
      ELSE NULL
    END AS spo2_category
  FROM
    avg_spo2
),

-- Get creatinine measurements for AKI detection
creatinine_measurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS creatinine_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    first_icu_stays s ON l.subject_id = s.subject_id AND l.hadm_id = s.hadm_id
  WHERE
    l.itemid = 50912  -- Creatinine
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN TIMESTAMP_SUB(s.intime, INTERVAL 7 DAY) AND TIMESTAMP_ADD(s.intime, INTERVAL 7 DAY)
),

-- Calculate baseline and peak creatinine
creatinine_stats AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(creatinine_value) AS baseline_creatinine,
    MAX(creatinine_value) AS peak_creatinine
  FROM
    creatinine_measurements
  GROUP BY
    subject_id, hadm_id
),

-- Identify AKI cases (simplified approach)
aki_cases AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    creatinine_stats
  WHERE
    peak_creatinine >= 1.5 * baseline_creatinine
    OR peak_creatinine - baseline_creatinine >= 0.3
)

-- Final result with counts and AKI rates
SELECT
  sc.spo2_category,
  COUNT(DISTINCT sc.subject_id) AS patient_count,
  COUNT(DISTINCT a.subject_id) AS aki_count,
  ROUND(COUNT(DISTINCT a.subject_id) / COUNT(DISTINCT sc.subject_id) * 100, 2) AS aki_rate_percentage
FROM
  spo2_categories sc
LEFT JOIN
  aki_cases a ON sc.subject_id = a.subject_id
GROUP BY
  sc.spo2_category
ORDER BY
  CASE sc.spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;