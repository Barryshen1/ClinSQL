WITH female_patients_39_49 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 39 AND 49
),

icu_stays AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients_39_49 p ON s.subject_id = p.subject_id
),

respiratory_rates AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.stay_id = s.stay_id
  WHERE
    ce.itemid IN (220210, 224689) -- Respiratory Rate itemids
    AND ce.valuenum BETWEEN 5 AND 50 -- Filter unreasonable values
),

mean_rr_per_stay AS (
  SELECT
    stay_id,
    AVG(respiratory_rate) AS mean_respiratory_rate
  FROM
    respiratory_rates
  GROUP BY
    stay_id
)

SELECT
  PERCENTILE_CONT(mean_respiratory_rate, 0.75) OVER() AS p75_mean_respiratory_rate
FROM
  mean_rr_per_stay
LIMIT 1;