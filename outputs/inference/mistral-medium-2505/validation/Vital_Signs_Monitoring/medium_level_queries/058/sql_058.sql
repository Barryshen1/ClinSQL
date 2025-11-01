WITH
-- Get the itemid for systolic BP (assuming 220050; verify in d_items)
systolic_bp_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Systolic Blood Pressure'
  LIMIT 1
),

-- Filter female ICU stays aged 38-48
female_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission
    EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48
),

-- Get systolic BP measurements in the first 24 hours of ICU stay
systolic_bp_measurements AS (
  SELECT
    f.stay_id,
    c.valuenum AS systolic_bp,
    c.charttime
  FROM female_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  JOIN systolic_bp_item s
    ON c.itemid = s.itemid
  WHERE c.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
),

-- Calculate average systolic BP per stay
avg_systolic_bp_per_stay AS (
  SELECT
    stay_id,
    AVG(systolic_bp) AS avg_systolic_bp
  FROM systolic_bp_measurements
  GROUP BY stay_id
  HAVING COUNT(systolic_bp) > 0  -- Ensure at least one measurement
),

-- Calculate percentiles
percentiles AS (
  SELECT
    avg_systolic_bp,
    PERCENT_RANK() OVER (ORDER BY avg_systolic_bp) AS percentile
  FROM avg_systolic_bp_per_stay
)

-- Get the percentile for 120 mmHg
SELECT
  percentile * 100 AS percentile_120_mmHg
FROM percentiles
WHERE avg_systolic_bp = 120;