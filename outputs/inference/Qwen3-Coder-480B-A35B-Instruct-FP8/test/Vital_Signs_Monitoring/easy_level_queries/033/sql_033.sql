SELECT
  APPROX_QUANTILES(heart_rate, 4)[ORDINAL(3)] - APPROX_QUANTILES(heart_rate, 4)[ORDINAL(1)] AS iqr_heart_rate
FROM (
  SELECT
    ce.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND di.label LIKE '%Heart Rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
);