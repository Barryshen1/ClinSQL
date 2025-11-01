WITH eligible_hadm AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

map_events AS (
  SELECT
    ce.hadm_id,
    ce.valuenum AS map_val
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    di.label LIKE '%Mean Blood Pressure%'
    AND ce.valuenum IS NOT NULL
),

hadm_max_map AS (
  SELECT
    eh.hadm_id,
    MAX(me.map_val) AS max_map
  FROM
    eligible_hadm AS eh
    JOIN map_events AS me
      ON eh.hadm_id = me.hadm_id
  GROUP BY
    eh.hadm_id
)

SELECT
  (APPROX_QUANTILES(max_map, 2))[OFFSET(1)] AS median_max_map
FROM
  hadm_max_map;