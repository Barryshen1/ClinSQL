WITH spo2_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    di.abbreviation = 'SpO2'
    AND ce.valuenum IS NOT NULL
),
stay_avg AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(valuenum) AS avg_spo2
  FROM
    spo2_events
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
),
cohort AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.stay_id,
    sa.avg_spo2
  FROM
    stay_avg sa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON sa.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
)
SELECT
  100.0 * SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank
FROM
  cohort;