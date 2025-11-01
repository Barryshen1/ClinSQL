WITH rr_items AS (
  -- Identify likely respiratory rate itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    -- look for common respiratory-rate terms or RR abbreviation
    LOWER(label) LIKE '%respir%' 
    OR LOWER(label) LIKE '%resp rate%'
    OR LOWER(label) LIKE '%respiration%'
    OR LOWER(COALESCE(abbreviation, '')) LIKE '%rr%'
),

per_stay_rr AS (
  -- Compute per-stay average RR within the first 48 hours of the ICU stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(c.valuenum) AS avg_rr,
    COUNT(1) AS n_measurements
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id
    AND s.hadm_id = c.hadm_id
    AND s.stay_id = c.stay_id
  WHERE
    c.itemid IN (SELECT itemid FROM rr_items)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id
),

eligible_stays AS (
  -- Filter to male patients aged 68-78 (inclusive)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    r.stay_id,
    r.avg_rr,
    r.n_measurements
  FROM per_stay_rr r
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON r.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
)

-- Compute percentile position of the value 12 breaths/min
SELECT
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_rr <= 12 THEN 1 ELSE 0 END) AS stays_with_avg_le_12,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN avg_rr <= 12 THEN 1 ELSE 0 END), COUNT(*)), 2) AS percentile_of_12_percent
FROM eligible_stays;