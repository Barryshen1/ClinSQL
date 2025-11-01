SELECT
  MAX(ce.valuenum) AS max_respiratory_rate_first_24h
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id    = icu.hadm_id
   AND ce.stay_id    = icu.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 38 AND 48
  AND p.anchor_age = 43
  AND di.label = 'Respiratory Rate'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime BETWEEN icu.intime
                      AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR);