WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.intime,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),
systolic_measurements AS (
  SELECT
    ch.stay_id,
    ch.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ch
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ch.itemid = di.itemid
  JOIN
    cohort co
  ON
    ch.stay_id = co.stay_id
  WHERE
    di.label LIKE '%systolic%'
    AND di.category = 'Routine Vital Signs'
    AND ch.valuenum IS NOT NULL
    AND ch.valuenum > 0
    AND ch.valuenum < 300
    AND ch.charttime >= co.intime
    AND ch.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
),
avg_systolic_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_systolic
  FROM
    systolic_measurements
  GROUP BY
    stay_id
)
SELECT
  (COUNTIF(avg_systolic < 130) * 100.0 / COUNT(*)) AS percentile_rank_130
FROM
  avg_systolic_per_stay;