WITH map_itemids AS (
  -- Identify likely MAP itemids from d_items (ICU module)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    LOWER(label) LIKE '%mean arterial%' 
    OR LOWER(label) LIKE '%mean arterial pressure%' 
    OR LOWER(label) LIKE '%map%'
    OR LOWER(IFNULL(abbreviation, '')) LIKE '%map%'
  )
),
per_stay_map AS (
  -- Compute per-stay mean MAP during the first 48 hours of the ICU stay
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    AVG(c.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id
    AND i.hadm_id = c.hadm_id
    AND i.stay_id = c.stay_id
  JOIN map_itemids m
    ON c.itemid = m.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND c.valuenum IS NOT NULL
    AND c.charttime >= i.intime
    AND c.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
  HAVING COUNT(1) >= 1
),
categorized AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM per_stay_map
)
SELECT
  map_category AS category,
  COUNT(*) AS stay_count,
  ROUND(AVG(mean_map), 2) AS mean_of_mean_map,
  -- APPROX_QUANTILES(mean_map, 4) returns [min, Q1, Q2(median), Q3, max]
  APPROX_QUANTILES(mean_map, 4)[OFFSET(2)] AS median_of_mean_map,
  (APPROX_QUANTILES(mean_map, 4)[OFFSET(3)] - APPROX_QUANTILES(mean_map, 4)[OFFSET(1)]) AS iqr_of_mean_map
FROM categorized
GROUP BY map_category
ORDER BY
  -- order categories logically
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
    ELSE 5
  END;