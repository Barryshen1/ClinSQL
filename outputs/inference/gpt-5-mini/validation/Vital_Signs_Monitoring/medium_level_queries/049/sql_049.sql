WITH systolic_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND (LOWER(unitname) LIKE '%mmhg%' OR LOWER(unitname) LIKE '%mm hg%')
),

icu_cohort AS (
  -- female patients aged 38-48 (inclusive) who had ICU stays
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

systolic_events AS (
  -- systolic BP events in the first 48 hours of the ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN systolic_itemids si
    ON ce.itemid = si.itemid
  JOIN icu_cohort icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    -- within first 48 hours of ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    -- plausible physiologic range to exclude obvious entry errors
    AND ce.valuenum BETWEEN 30 AND 300
),

per_stay_avg AS (
  -- per-stay average systolic BP over first 48 hours
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_sbp
  FROM systolic_events
  GROUP BY stay_id, subject_id, hadm_id
)

SELECT
  COUNT(*) AS total_stays_with_systolic_in_first_48h,
  SUM(CASE WHEN avg_sbp <= 130 THEN 1 ELSE 0 END) AS stays_with_avg_sbp_leq_130,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN avg_sbp <= 130 THEN 1 ELSE 0 END), COUNT(*)), 2) AS percentile_of_130_pct
FROM per_stay_avg;