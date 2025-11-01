WITH filtered_data AS (
  SELECT
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= TIMESTAMP_ADD(icu.intime, INTERVAL 1 DAY)
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS q
  FROM
    filtered_data
)
SELECT
  q[OFFSET(3)] - q[OFFSET(1)] AS heart_rate_iqr_bpm
FROM
  quantiles;