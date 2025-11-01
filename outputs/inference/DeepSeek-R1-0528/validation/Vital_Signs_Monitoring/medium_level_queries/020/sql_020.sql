WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    -- Calculate age at ICU admission: anchor_age + (current admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT stay_id, intime
  FROM cohort
  WHERE age BETWEEN 58 AND 68  -- Age filter: 58-68 years
),
map_data AS (
  SELECT 
    fc.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fc.stay_id = ce.stay_id
    AND ce.itemid IN (220052, 220181)  -- MAP itemIDs
    AND ce.valuenum IS NOT NULL        -- Exclude non-numeric values
    AND ce.charttime >= fc.intime      -- ICU admission start
    AND ce.charttime < DATETIME_ADD(fc.intime, INTERVAL 48 HOUR)  -- First 48 hours
  GROUP BY fc.stay_id
)
SELECT 
  ROUND(
    SAFE_DIVIDE(COUNTIF(mean_map <= 85) * 100.0, COUNT(*)),
    2
  ) AS percentile
FROM map_data;