WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.gender,
    p.anchor_age,
    DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON
    icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 58 AND 68
),

map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'map'
),

map_data AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_map_48h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    map_items m
  ON
    ce.itemid = m.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

percentile_data AS (
  SELECT
    mean_map_48h,
    PERCENT_RANK() OVER (ORDER BY mean_map_48h) AS percentile_rank
  FROM
    map_data
)

SELECT
  APPROX_TOP_COUNT(
    CASE WHEN mean_map_48h <= 85 THEN percentile_rank END,
    1
  )[OFFSET(0)].value AS percentile_of_85
FROM
  percentile_data
CROSS JOIN
  (SELECT 85 AS target_map) target
WHERE
  mean_map_48h IS NOT NULL;