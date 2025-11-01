SELECT
  MIN(ce.valuenum) AS min_heart_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON p.subject_id = icu.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON icu.subject_id = ce.subject_id
  AND icu.hadm_id = ce.hadm_id
  AND icu.stay_id = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND di.label = 'Heart Rate'
  AND ce.valuenum IS NOT NULL
  AND TIMESTAMP_DIFF(ce.charttime, icu.intime, HOUR) BETWEEN 0 AND 24;