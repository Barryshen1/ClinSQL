WITH map_itemids AS (
  -- Identify MAP-related itemids in the ICU items dictionary
  SELECT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    -- require 'mean' and either 'arterial' or 'blood pressure' to avoid other "mean" measurements
    (LOWER(label) LIKE '%mean%' AND (LOWER(label) LIKE '%arterial%' OR LOWER(label) LIKE '%blood pressure%'))
    -- or explicit abbreviation 'MAP'
    OR LOWER(COALESCE(abbreviation, '')) = 'map'
  )
),
map_measurements_first24 AS (
  -- MAP measurements occurring within the first 24 hours of the ICU stay
  SELECT
    isc.subject_id,
    isc.hadm_id,
    isc.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` isc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = isc.stay_id
  JOIN map_itemids di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = isc.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= isc.intime
    AND ce.charttime <= TIMESTAMP_ADD(isc.intime, INTERVAL 24 HOUR)
),
per_stay_map AS (
  -- Compute per-stay mean MAP over the first 24 hours
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS n_measurements,
    AVG(valuenum) AS mean_map_first24
  FROM map_measurements_first24
  GROUP BY subject_id, hadm_id, stay_id
)
-- Final aggregation: average of per-stay means (each stay weighted equally),
-- plus counts for context.
SELECT
  COUNT(DISTINCT subject_id) AS n_subjects,
  COUNT(DISTINCT stay_id) AS n_stays,
  SUM(n_measurements) AS total_map_measurements,
  ROUND(AVG(mean_map_first24), 2) AS avg_map_first24_across_stays,
  ROUND(STDDEV_POP(mean_map_first24), 2) AS sd_map_first24_across_stays
FROM per_stay_map;