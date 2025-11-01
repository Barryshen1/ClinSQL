WITH
-- Get female ICU patients aged 62-72
female_icu_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    p.anchor_age + EXTRACT(YEAR FROM s.intime - DATE(p.anchor_year, 1, 1)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM s.intime - DATE(p.anchor_year, 1, 1)) BETWEEN 62 AND 72
),

-- Get temperature measurements in first 24 hours
first_24h_temps AS (
  SELECT
    f.subject_id,
    f.stay_id,
    c.charttime,
    CASE
      WHEN c.itemid = 223761 THEN (c.valuenum - 32) * 5/9  -- Convert F to C
      WHEN c.itemid = 223762 THEN c.valuenum  -- Already in C
    END AS temp_c,
    CASE
      WHEN (c.itemid = 223761 AND (c.valuenum - 32) * 5/9 < 36.0) OR
           (c.itemid = 223762 AND c.valuenum < 36.0) THEN '<36.0'
      WHEN (c.itemid = 223761 AND (c.valuenum - 32) * 5/9 BETWEEN 36.0 AND 37.9) OR
           (c.itemid = 223762 AND c.valuenum BETWEEN 36.0 AND 37.9) THEN '36.0-37.9'
      WHEN (c.itemid = 223761 AND (c.valuenum - 32) * 5/9 >= 38.0) OR
           (c.itemid = 223762 AND c.valuenum >= 38.0) THEN '>=38.0'
    END AS temp_category
  FROM
    female_icu_patients f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON
    f.subject_id = c.subject_id AND f.stay_id = c.stay_id
  WHERE
    c.itemid IN (223761, 223762)  -- Temperature F and C
    AND c.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
),

-- Identify patients with AKI (simplified approach)
aki_patients AS (
  SELECT DISTINCT
    l.subject_id,
    l.hadm_id,
    f.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    female_icu_patients f
  ON
    l.subject_id = f.subject_id AND l.hadm_id = f.hadm_id
  WHERE
    l.itemid = 50912  -- Creatinine
    AND l.valuenum IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2
      WHERE
        l2.subject_id = l.subject_id
        AND l2.hadm_id = l.hadm_id
        AND l2.itemid = 50912
        AND l2.charttime > l.charttime
        AND l2.charttime <= TIMESTAMP_ADD(l.charttime, INTERVAL 48 HOUR)
        AND (l2.valuenum - l.valuenum) >= 0.3  -- KDIGO criterion 1
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2
      WHERE
        l2.subject_id = l.subject_id
        AND l2.hadm_id = l.hadm_id
        AND l2.itemid = 50912
        AND l2.charttime > l.charttime
        AND l2.charttime <= TIMESTAMP_ADD(l.charttime, INTERVAL 7 DAY)
        AND l2.valuenum >= 1.5 * l.valuenum  -- KDIGO criterion 2
    )
)

-- Final aggregation
SELECT
  temp_category,
  COUNT(*) AS measurement_count,
  ROUND(AVG(temp_c), 2) AS mean_temp,
  ROUND(PERCENTILE_CONT(temp_c, 0.5), 2) AS median_temp,
  ROUND(PERCENTILE_CONT(temp_c, 0.25), 2) AS q1_temp,
  ROUND(PERCENTILE_CONT(temp_c, 0.75), 2) AS q3_temp,
  ROUND((COUNT(DISTINCT CASE WHEN a.subject_id IS NOT NULL THEN t.subject_id END) /
         COUNT(DISTINCT t.subject_id)) * 100, 2) AS aki_rate_percentage
FROM
  first_24h_temps t
LEFT JOIN
  aki_patients a
ON
  t.subject_id = a.subject_id
GROUP BY
  temp_category
ORDER BY
  temp_category;