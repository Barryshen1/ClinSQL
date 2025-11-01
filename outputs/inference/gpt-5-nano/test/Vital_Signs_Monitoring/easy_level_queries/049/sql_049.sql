WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` AS di
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
),
per_stay_map_mean AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(ce.valuenum) AS map_mean_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = s.subject_id
   AND ce.hadm_id = s.hadm_id
   AND ce.stay_id = s.stay_id
  JOIN map_items AS mi
    ON ce.itemid = mi.itemid
  WHERE ce.charttime >= s.intime
    AND ce.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND ce.valuenum IS NOT NULL
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
)
SELECT STDDEV_SAMP(map_mean_24h) AS sd_first_24h_map
FROM per_stay_map_mean;