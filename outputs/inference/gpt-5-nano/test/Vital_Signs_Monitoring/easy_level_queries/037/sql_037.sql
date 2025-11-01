WITH cohort AS (
  -- ICU stays for females aged 89-99
  SELECT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 89 AND 99
),
map_items AS (
  -- MAP-related itemids from the ICU item catalog
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
)
-- Compute per-stay mean MAP in first 24 hours, then average across stays
SELECT AVG(stay_mean_map) AS avg_map_24h
FROM (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS stay_mean_map
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM map_items)
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
) AS per_stay;