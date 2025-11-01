WITH map_items AS (
  -- Identify itemids that likely represent Mean Arterial Pressure (MAP)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    -- match common label/abbreviation patterns for MAP
    LOWER(label) LIKE '%mean arterial%' 
    OR LOWER(label) LIKE '%mean arterial pressure%'
    OR LOWER(abbreviation) LIKE '%map%'
),

per_stay_avg_map AS (
  -- Compute per-stay average MAP (include subject_id to join to patients)
  SELECT
    icu.stay_id,
    icu.subject_id,
    AVG(ce.valuenum) AS avg_map,
    COUNT(ce.valuenum) AS n_measurements
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 300  -- reasonable physiologic filter
    AND ce.itemid IN (SELECT itemid FROM map_items)
  GROUP BY icu.stay_id, icu.subject_id
),

eligible_stays AS (
  -- Keep only male patients aged 38-48 (inclusive)
  SELECT
    p.subject_id,
    s.stay_id,
    s.avg_map
  FROM per_stay_avg_map s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
)

SELECT
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END) AS stays_avg_map_le_60,
  SAFE_DIVIDE(
    SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS proportion_le_60
FROM eligible_stays;