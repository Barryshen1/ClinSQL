SELECT
  MIN(ce.valuenum) AS min_respiratory_rate_first_24h
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS i
  ON ce.subject_id = i.subject_id
  AND ce.hadm_id = i.hadm_id
  AND ce.stay_id = i.stay_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON ce.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
WHERE
  LOWER(di.label) LIKE '%respiratory rate%'
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 39 AND 49
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= i.intime
  AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR);