WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
),
stay_avg_map AS (
  SELECT
    c.stay_id,
    AVG(e.valuenum) AS avg_map
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS e
    ON c.subject_id = e.subject_id
   AND c.stay_id = e.stay_id
  JOIN map_itemids AS di
    ON e.itemid = di.itemid
  WHERE e.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT
  COUNTIF(avg_map <= 60) / NULLIF(COUNT(*), 0) AS percentile_rank
FROM stay_avg_map;