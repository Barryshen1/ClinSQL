SELECT
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS heart_rate_iqr
FROM
  `physionet-data.mimiciv_3_1_icu`.icustays AS icu
JOIN
  `physionet-data.mimiciv_3_1_hosp`.patients AS p
  ON icu.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.chartevents AS ce
  ON icu.stay_id = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.d_items AS di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 45 AND 55
  AND di.label = 'Heart Rate'
  AND ce.charttime >= icu.intime + INTERVAL 2 DAY
  AND ce.charttime <= icu.outtime
  AND ce.valuenum IS NOT NULL;