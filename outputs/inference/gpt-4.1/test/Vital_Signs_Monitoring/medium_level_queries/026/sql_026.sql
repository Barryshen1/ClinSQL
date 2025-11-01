WITH male_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
),
rr_measurements AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE
    ce.itemid IN (220210, 224690)
    AND ce.valuenum IS NOT NULL
),
rr_first48 AS (
  SELECT
    s.stay_id,
    rr.valuenum
  FROM
    male_icu_stays s
  INNER JOIN
    rr_measurements rr
    ON s.stay_id = rr.stay_id
    AND rr.charttime >= s.intime
    AND rr.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),
avg_rr_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM
    rr_first48
  GROUP BY
    stay_id
  HAVING
    COUNT(valuenum) > 0
)
SELECT
  ROUND(100.0 * SUM(CASE WHEN avg_rr <= 12 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_12_rr
FROM
  avg_rr_per_stay;