WITH
-- Get female patients aged 45-55
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 45 AND 55
),

-- Get their ICU stays
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

-- Get SBP measurements in first 24 hours of each stay
sbp_measurements AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220050  -- SBP itemid
    AND c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
),

-- Calculate average SBP per stay
avg_sbp_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM
    sbp_measurements
  GROUP BY
    subject_id, stay_id
),

-- Categorize the average SBP
sbp_categories AS (
  SELECT
    subject_id,
    CASE
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN avg_sbp >= 160 THEN '>=160'
      ELSE NULL
    END AS sbp_category
  FROM
    avg_sbp_per_stay
)

-- Count unique patients in each category
SELECT
  sbp_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM
  sbp_categories
WHERE
  sbp_category IS NOT NULL
GROUP BY
  sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;