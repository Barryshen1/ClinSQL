WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year BETWEEN 67 AND 77
),
temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND (LOWER(label) LIKE '%celsius%' OR LOWER(label) LIKE '%c%')
),
stay_temperatures AS (
  SELECT
    co.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM
    cohort co
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    co.stay_id = ce.stay_id
  JOIN
    temperature_items ti
  ON
    ce.itemid = ti.itemid
  WHERE
    ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 20
    AND ce.valuenum < 45
  GROUP BY
    co.stay_id
)
SELECT
  (
    SELECT
      CAST(SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) AS FLOAT64) * 100.0 / COUNT(*)
    FROM
      stay_temperatures
  ) AS percentile_36C
FROM
  stay_temperatures
LIMIT 1;