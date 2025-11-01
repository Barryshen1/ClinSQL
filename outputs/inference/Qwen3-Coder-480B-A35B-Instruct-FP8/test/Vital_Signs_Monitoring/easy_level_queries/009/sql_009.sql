SELECT
  APPROX_QUANTILES(c.valuenum, 100)[OFFSET(75)] AS temperature_75th_percentile
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON p.subject_id = icu.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.chartevents c
  ON icu.stay_id = c.stay_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items d
  ON c.itemid = d.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 86 AND 96
  AND d.label LIKE '%Temperature Fahrenheit%'
  AND c.valuenum IS NOT NULL
  AND c.charttime >= icu.intime
  AND c.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);