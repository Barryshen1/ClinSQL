WITH cohort AS (
  SELECT
    icu.stay_id,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),

map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
    AND linksto = 'chartevents'
),

first_map AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS map_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    map_items mi
  ON
    ce.itemid = mi.itemid
  WHERE
    ce.charttime IS NOT NULL
    AND ce.valuenum IS NOT NULL
)

SELECT
  APPROX_QUANTILES(map_value, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(map_value, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(map_value, 4)[OFFSET(3)] - APPROX_QUANTILES(map_value, 4)[OFFSET(1)] AS IQR
FROM
  first_map
WHERE
  rn = 1;