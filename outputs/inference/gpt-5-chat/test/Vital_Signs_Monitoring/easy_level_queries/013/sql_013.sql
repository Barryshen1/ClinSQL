SELECT
  MIN(ce.valuenum) AS min_heart_rate
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ce.stay_id = icu.stay_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON icu.subject_id = pat.subject_id
WHERE
  di.label = 'Heart Rate'
  AND di.category = 'Vital Signs'
  AND pat.gender = 'F'
  AND pat.anchor_age BETWEEN 44 AND 54
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.charttime >= icu.intime
  AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR);