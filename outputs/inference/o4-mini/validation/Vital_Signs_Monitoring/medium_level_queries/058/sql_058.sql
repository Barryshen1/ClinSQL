WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),
systolic_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%systolic%'
),
avg_sbp AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
     AND ce.charttime >= c.intime
     AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    JOIN systolic_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
)
SELECT
  120 AS target_sbp,
  COUNTIF(s.avg_sbp <= 120) * 100.0 / COUNT(*) AS percentile_of_120
FROM
  avg_sbp AS s;