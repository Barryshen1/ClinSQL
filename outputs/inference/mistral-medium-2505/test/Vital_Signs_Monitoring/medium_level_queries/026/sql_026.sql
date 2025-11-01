WITH
-- Get respiratory rate itemid (220210 is known to be respiratory rate)
respiratory_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Respiratory Rate'
),

-- Get male ICU stays with age between 68-78 at ICU admission
male_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    p.gender,
    -- Calculate age at ICU admission
    EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
),

-- Get respiratory rate measurements in first 48 hours of ICU stay
respiratory_rates AS (
  SELECT
    m.stay_id,
    ce.charttime,
    ce.valuenum AS respiratory_rate
  FROM male_icu_stays m
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON m.stay_id = ce.stay_id
  JOIN respiratory_rate_item rri
    ON ce.itemid = rri.itemid
  WHERE ce.charttime BETWEEN m.icu_intime
    AND TIMESTAMP_ADD(m.icu_intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate average respiratory rate per ICU stay
avg_respiratory_rates AS (
  SELECT
    stay_id,
    AVG(respiratory_rate) AS avg_respiratory_rate
  FROM respiratory_rates
  GROUP BY stay_id
  HAVING COUNT(respiratory_rate) > 0  -- Ensure we have at least one measurement
),

-- Calculate percentiles
percentiles AS (
  SELECT
    avg_respiratory_rate,
    PERCENT_RANK() OVER (ORDER BY avg_respiratory_rate) AS percentile
  FROM avg_respiratory_rates
)

-- Find the percentile for 12 breaths/min
SELECT
  ROUND(percentile * 100, 2) AS percentile_for_12_bpm
FROM percentiles
WHERE avg_respiratory_rate = 12;