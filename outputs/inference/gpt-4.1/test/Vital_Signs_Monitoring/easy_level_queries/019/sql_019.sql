WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.hadm_id,
    i.stay_id,
    i.first_careunit
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(i.first_careunit) IN ('stepdown', 'imc')
),

map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%arterial blood pressure mean%'
),

map_per_stay AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(e.valuenum) AS mean_map
  FROM
    cohort c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND c.stay_id = e.stay_id
  WHERE
    e.itemid IN (SELECT itemid FROM map_itemids)
    AND e.valuenum IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
)

SELECT
  AVG(mean_map) AS avg_of_mean_map_per_stay
FROM
  map_per_stay;