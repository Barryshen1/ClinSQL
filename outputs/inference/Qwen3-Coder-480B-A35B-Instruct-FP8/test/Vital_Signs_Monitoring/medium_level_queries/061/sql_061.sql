WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'map'
),
icu_map_data AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    AVG(ce.valuenum) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
  GROUP BY icu.stay_id, icu.subject_id
)
SELECT
  AVG(CASE WHEN avg_map <= 60 THEN 1.0 ELSE 0.0 END) AS percentile_rank
FROM icu_map_data;