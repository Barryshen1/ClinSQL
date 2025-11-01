WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
eligible_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
      ON p.subject_id = s.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
)
, stay_max_map AS (
  SELECT
    es.stay_id,
    MAX(ce.valuenum) AS max_map
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON es.subject_id = ce.subject_id
     AND es.hadm_id    = ce.hadm_id
     AND es.stay_id    = ce.stay_id
    JOIN map_items mi
      ON ce.itemid = mi.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    es.stay_id
)
SELECT
  AVG(max_map) AS avg_of_max_map
FROM
  stay_max_map;