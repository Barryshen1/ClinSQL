SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS temp_75th_percentile_f
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 86 AND 96
  AND ce.charttime >= icu.intime
  AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND LOWER(di.label) LIKE '%temperature%'
  AND UPPER(ce.valueuom) IN ('F', 'FAHRENHEIT')
  AND ce.valuenum IS NOT NULL;