WITH map_itemids AS (
  -- Identify candidate MAP itemids from ICU d_items
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
    OR LOWER(label) LIKE '%arterial bp mean%'
    OR LOWER(label) LIKE '%mean bp%'
    OR LOWER(label) LIKE '%map%'
    OR LOWER(abbreviation) LIKE '%map%'
),

map_measurements AS (
  -- MAP measurements during the first 48 hours of each ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id
   AND c.hadm_id = icu.hadm_id
   AND c.stay_id = icu.stay_id
  JOIN map_itemids m
    ON c.itemid = m.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

per_stay_avg AS (
  -- Per-stay average MAP in first 48 hours, only stays with >= 3 MAP measurements
  SELECT
    ms.stay_id,
    ms.subject_id,
    ms.hadm_id,
    AVG(ms.valuenum) AS avg_map,
    COUNT(*) AS n_meas
  FROM map_measurements ms
  GROUP BY ms.stay_id, ms.subject_id, ms.hadm_id
  HAVING COUNT(*) >= 3
),

cohort AS (
  -- Restrict to male patients aged 83-93
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
)

SELECT
  60.0 AS target_map_mmHg,
  COUNT(*) AS total_stays_in_cohort,
  SUM(CASE WHEN psa.avg_map <= 60 THEN 1 ELSE 0 END) AS n_stays_leq_60,
  ROUND(
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN psa.avg_map <= 60 THEN 1 ELSE 0 END), COUNT(*)),
    2
  ) AS percentile_of_60
FROM per_stay_avg psa
JOIN cohort
  ON psa.subject_id = cohort.subject_id;