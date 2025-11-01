WITH spo2_items AS (
  -- Identify itemids likely to represent SpO2 / pulse oximetry
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2 sat%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(label) LIKE '%oximeter%'
     OR LOWER(label) LIKE '%pulse ox%'
),
spo2_events AS (
  -- Pull numeric SpO2 measurements from ICU chartevents for those itemids
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spo2_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- Restrict to plausible SpO2 range to reduce erroneous values
    AND ce.valuenum BETWEEN 50 AND 100
    -- Ensure the event is tied to an ICU stay
    AND ce.stay_id IS NOT NULL
),
per_stay_avg AS (
  -- Compute stay-level average SpO2 (only stays with at least one valid measurement)
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_spo2,
    COUNT(*) AS n_obs
  FROM spo2_events
  GROUP BY stay_id, subject_id, hadm_id
),
cohort_stays AS (
  -- Female patients aged 80-90 and their ICU stays
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
)
-- Calculate the percentile: percent of cohort stays with avg_spo2 <= 88
SELECT
  COUNT(*) AS total_stays_with_spo2,                               -- denominator
  SUM(CASE WHEN psa.avg_spo2 <= 88 THEN 1 ELSE 0 END) AS num_leq_88, -- numerator
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN psa.avg_spo2 <= 88 THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100.0,
    2
  ) AS pct_stays_avg_spo2_leq_88
FROM cohort_stays cs
JOIN per_stay_avg psa
  ON cs.stay_id = psa.stay_id;