WITH
-- Get female patients aged 75-85
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),

-- Get their ICU stays
female_icu_stays AS (
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
    female_patients p ON s.subject_id = p.subject_id
),

-- Get systolic BP measurements (itemid 220050 is systolic BP)
systolic_bp AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE
    c.itemid = 220050  -- Systolic BP
    AND d.label = 'Systolic Blood Pressure'
),

-- Calculate mean systolic BP per stay in first 48 hours
stay_bp_stats AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    AVG(CASE WHEN TIMESTAMP_DIFF(b.charttime, s.intime, HOUR) <= 48 THEN b.systolic_bp ELSE NULL END) AS mean_sbp_first_48h,
    COUNT(CASE WHEN TIMESTAMP_DIFF(b.charttime, s.intime, HOUR) <= 48 THEN b.systolic_bp ELSE NULL END) AS bp_count
  FROM
    female_icu_stays s
  LEFT JOIN
    systolic_bp b ON s.stay_id = b.stay_id
  GROUP BY
    s.stay_id, s.subject_id, s.hadm_id
  HAVING
    bp_count > 0  -- Only include stays with at least one BP measurement
),

-- Calculate percentiles
percentiles AS (
  SELECT
    mean_sbp_first_48h,
    PERCENT_RANK() OVER (ORDER BY mean_sbp_first_48h) AS percentile
  FROM
    stay_bp_stats
)

-- Find where 140 mmHg falls in the distribution
SELECT
  ROUND(AVG(percentile) * 100, 2) AS percentile_for_140_mmHg,
  COUNT(*) AS number_of_stays_analyzed
FROM
  percentiles
WHERE
  mean_sbp_first_48h <= 140;