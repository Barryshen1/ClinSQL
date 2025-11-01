WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%' OR LOWER(label) = 'map'
),
max_map_per_stay AS (
  SELECT
    c.hadm_id,
    MAX(ce.valuenum) AS max_map
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
      AND c.hadm_id = ce.hadm_id
    INNER JOIN map_itemids mi
      ON ce.itemid = mi.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    c.hadm_id
)
SELECT
  APPROX_QUANTILES(max_map, 2)[OFFSET(1)] AS median_max_map
FROM
  max_map_per_stay
;