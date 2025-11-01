SELECT
  MAX(ce.valuenum) AS max_respiratory_rate
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON p.subject_id = icu.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62
  AND di.label = 'Respiratory Rate'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 1 DAY);