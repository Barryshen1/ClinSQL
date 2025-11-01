WITH male_icu_patients AS (
  -- Get male patients aged 54-64 with ICU stays
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),

rr_data AS (
  -- Get RR measurements in first 48 hours of ICU stay
  SELECT
    m.stay_id,
    c.charttime,
    c.valuenum AS rr_value
  FROM
    male_icu_patients m
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON
    m.subject_id = c.subject_id
    AND m.hadm_id = c.hadm_id
    AND m.stay_id = c.stay_id
  WHERE
    c.itemid = 220210  -- RR itemid
    AND c.charttime BETWEEN m.intime AND TIMESTAMP_ADD(m.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
),

avg_rr_per_stay AS (
  -- Calculate average RR per stay
  SELECT
    stay_id,
    AVG(rr_value) AS avg_rr
  FROM
    rr_data
  GROUP BY
    stay_id
),

percentiles AS (
  -- Calculate overall percentiles
  SELECT
    PERCENTILE_CONT(avg_rr, 0.25) OVER() AS q1_rr,
    PERCENTILE_CONT(avg_rr, 0.5) OVER() AS median_rr,
    PERCENTILE_CONT(avg_rr, 0.75) OVER() AS q3_rr,
    PERCENTILE_CONT(avg_rr, 0.75) OVER() - PERCENTILE_CONT(avg_rr, 0.25) OVER() AS iqr_rr
  FROM
    avg_rr_per_stay
  LIMIT 1
)

-- Categorize and aggregate results
SELECT
  CASE
    WHEN a.avg_rr < 12 THEN '<12'
    WHEN a.avg_rr BETWEEN 12 AND 20 THEN '12-20'
    WHEN a.avg_rr BETWEEN 21 AND 29 THEN '21-29'
    WHEN a.avg_rr >= 30 THEN '>=30'
    ELSE 'Unknown'
  END AS rr_category,
  COUNT(a.stay_id) AS n,
  ROUND(AVG(a.avg_rr), 2) AS mean_rr,
  ROUND(p.median_rr, 2) AS median_rr,
  ROUND(p.q1_rr, 2) AS q1_rr,
  ROUND(p.q3_rr, 2) AS q3_rr,
  ROUND(p.iqr_rr, 2) AS iqr_rr
FROM
  avg_rr_per_stay a
CROSS JOIN
  percentiles p
GROUP BY
  rr_category,
  p.median_rr,
  p.q1_rr,
  p.q3_rr,
  p.iqr_rr
ORDER BY
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
    ELSE 5
  END;