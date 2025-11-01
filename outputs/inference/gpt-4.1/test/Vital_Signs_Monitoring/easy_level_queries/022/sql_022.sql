WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%map%' OR LOWER(label) LIKE '%mean arterial pressure%'
),
male_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
),
max_map_per_stay AS (
  SELECT
    s.stay_id,
    MAX(c.valuenum) AS max_map
  FROM male_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM map_itemids)
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
)
SELECT
  AVG(max_map) AS avg_max_map
FROM max_map_per_stay
WHERE max_map IS NOT NULL
;