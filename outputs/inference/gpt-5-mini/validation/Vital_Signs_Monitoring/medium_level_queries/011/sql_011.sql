WITH rr_itemids AS (
  SELECT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respirat%'  -- captures "Respiratory Rate", "Resp Rate", etc.
     OR LOWER(label) LIKE '%resp rate%'
     OR LOWER(abbreviation) = 'rr'
),

rr_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rr_itemids d ON ce.itemid = d.itemid
  WHERE ce.valuenum IS NOT NULL
),

-- RR measurements that fall within the first 48 hours of the ICU stay
first48_rr AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    re.charttime,
    re.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN rr_events re
    ON re.stay_id = s.stay_id
   AND re.subject_id = s.subject_id
   AND re.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),

-- Per-stay average RR (only stays with at least one RR in first 48h)
per_stay_avg AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_rr
  FROM first48_rr
  GROUP BY stay_id, subject_id, hadm_id
),

-- Restrict to male patients aged 54-64 (inclusive)
eligible_stays AS (
  SELECT psa.*
  FROM per_stay_avg psa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON psa.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
)

SELECT
  bin,
  COUNT(*) AS n_stays,
  ROUND(AVG(avg_rr), 2) AS mean_avg_rr,
  ROUND( (APPROX_QUANTILES(avg_rr, 100))[OFFSET(50)], 2) AS median_avg_rr,
  ROUND( (APPROX_QUANTILES(avg_rr, 100))[OFFSET(25)], 2) AS q1_avg_rr,
  ROUND( (APPROX_QUANTILES(avg_rr, 100))[OFFSET(75)], 2) AS q3_avg_rr,
  ROUND(
    (APPROX_QUANTILES(avg_rr, 100))[OFFSET(75)]
    - (APPROX_QUANTILES(avg_rr, 100))[OFFSET(25)]
  , 2) AS iqr_avg_rr
FROM (
  SELECT
    *,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr < 21 THEN '12-20'
      WHEN avg_rr >= 21 AND avg_rr < 30 THEN '21-29'
      ELSE '>=30'
    END AS bin,
    CASE
      WHEN avg_rr < 12 THEN 1
      WHEN avg_rr >= 12 AND avg_rr < 21 THEN 2
      WHEN avg_rr >= 21 AND avg_rr < 30 THEN 3
      ELSE 4
    END AS bin_order
  FROM eligible_stays
)
GROUP BY bin, bin_order
ORDER BY bin_order;