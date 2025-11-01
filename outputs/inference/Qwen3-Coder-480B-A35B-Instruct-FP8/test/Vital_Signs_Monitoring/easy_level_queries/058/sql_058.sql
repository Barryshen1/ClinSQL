SELECT
  APPROX_QUANTILES(min_temp_f, 2)[OFFSET(1)] AS median_min_temperature_f
FROM (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum * 9 / 5 + 32) AS min_temp_f
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    p.subject_id = icu.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%temperature%'
  GROUP BY
    ce.stay_id
);