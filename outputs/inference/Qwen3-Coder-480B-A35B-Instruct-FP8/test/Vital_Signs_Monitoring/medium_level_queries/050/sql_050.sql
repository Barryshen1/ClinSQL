WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age,
    DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age BETWEEN 67 AND 77
),

hr_measurements AS (
  SELECT
    ch.stay_id,
    AVG(ch.valuenum) AS avg_hr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ch
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ch.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    ch.stay_id = icu.stay_id
  WHERE
    di.label = 'Heart Rate'
    AND ch.valuenum IS NOT NULL
    AND ch.charttime >= icu.intime
    AND ch.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    ch.stay_id
),

hr_distribution AS (
  SELECT
    c.stay_id,
    h.avg_hr
  FROM
    cohort c
  JOIN
    hr_measurements h
  ON
    c.stay_id = h.stay_id
)

SELECT
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(100 - 1)] AS percentile_100,
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(90)] AS percentile_90,
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(75)] AS percentile_75,
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(avg_hr, 100)[OFFSET(10)] AS percentile_10,
  -- Approximate percentile of 110 bpm
  100 * (
    SELECT COUNT(*) FROM hr_distribution WHERE avg_hr <= 110
  ) / (
    SELECT COUNT(*) FROM hr_distribution
  ) AS percentile_of_110
FROM
  hr_distribution;