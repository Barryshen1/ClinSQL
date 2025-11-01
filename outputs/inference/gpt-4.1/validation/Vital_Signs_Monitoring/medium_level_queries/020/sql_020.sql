WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(abbreviation) = 'map'
),
female_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 58 AND 68
),
map_measurements AS (
  SELECT
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN map_itemids mi ON c.itemid = mi.itemid
  WHERE c.valuenum IS NOT NULL
),
map_48hr AS (
  SELECT
    s.stay_id,
    AVG(m.valuenum) AS mean_map_48hr
  FROM female_icu_stays s
  JOIN map_measurements m
    ON s.stay_id = m.stay_id
    AND m.charttime >= s.intime
    AND m.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
  HAVING COUNT(m.valuenum) > 0
),
percentile_calc AS (
  SELECT
    COUNTIF(mean_map_48hr < 85) AS num_below_85,
    COUNT(*) AS total_stays
  FROM map_48hr
)
SELECT
  SAFE_DIVIDE(num_below_85, total_stays) * 100 AS percentile_85mmHg
FROM percentile_calc;