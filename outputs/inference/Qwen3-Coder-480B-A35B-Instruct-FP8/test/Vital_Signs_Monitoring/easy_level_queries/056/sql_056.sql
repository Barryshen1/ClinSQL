SELECT
  APPROX_QUANTILES(temperature_f, 2)[OFFSET(1)] AS median_temperature_f
FROM (
  SELECT
    c.valuenum * 9/5 + 32 AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    p.subject_id = icu.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON
    icu.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
  ON
    c.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND c.charttime >= icu.intime
    AND c.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND LOWER(d.label) LIKE '%temperature%'
);