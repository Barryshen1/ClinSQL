WITH cohort AS (
  SELECT
    i.stay_id,
    p.subject_id,
    p.anchor_age,
    i.intime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

systolic_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%systolic%'
    AND linksto = 'chartevents'
),

systolic_measurements AS (
  SELECT
    c.stay_id,
    c.valuenum
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN
    systolic_items s
  ON
    c.itemid = s.itemid
  JOIN
    cohort co
  ON
    c.stay_id = co.stay_id
  WHERE
    c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime >= co.intime
    AND c.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
),

avg_systolic_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_systolic
  FROM
    systolic_measurements
  GROUP BY
    stay_id
),

percentile_calc AS (
  SELECT
    avg_systolic,
    PERCENT_RANK() OVER (ORDER BY avg_systolic) * 100 AS percentile
  FROM
    avg_systolic_per_stay
)

SELECT
  percentile
FROM
  percentile_calc
ORDER BY
  ABS(avg_systolic - 150)
LIMIT 1;