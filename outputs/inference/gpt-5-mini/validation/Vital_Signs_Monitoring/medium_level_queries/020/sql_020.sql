WITH map_itemids AS (
  -- Identify itemids that correspond to mean arterial pressure (MAP)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE 
    -- match common labels/abbreviations for mean arterial pressure
    LOWER(label) LIKE '%mean arterial%'
    OR LOWER(label) LIKE '%mean blood pressure%'
    OR LOWER(label) LIKE '%mean blood pressure%'
    OR LOWER(label) LIKE '%mean bp%'
    OR LOWER(abbreviation) LIKE '%map%'
    OR LOWER(label) LIKE '%map%'
),

female_icustays AS (
  -- ICU stays for female patients aged 58-68 (anchor_age) inclusive
  SELECT s.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

stay_map_stats AS (
  -- Compute the mean MAP per ICU stay within the first 48 hours of that stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(ce.valuenum) AS mean_map,
    COUNT(*) AS n_measurements
  FROM female_icustays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.stay_id = ce.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.charttime IS NOT NULL
    -- limit to first 48 hours of ICU stay
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    -- prefer mmHg units when present (allow NULL unit entries too)
    AND (LOWER(ce.valueuom) LIKE '%mmhg%' OR ce.valueuom IS NULL)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
  HAVING COUNT(*) >= 1
)

SELECT
  COUNT(*) AS total_stays_with_map,
  SUM(CASE WHEN mean_map <= 85 THEN 1 ELSE 0 END) AS stays_mean_map_le_85,
  SAFE_DIVIDE(SUM(CASE WHEN mean_map <= 85 THEN 1 ELSE 0 END), COUNT(*)) * 100.0 AS percentile_of_85_mmHg
FROM stay_map_stats;