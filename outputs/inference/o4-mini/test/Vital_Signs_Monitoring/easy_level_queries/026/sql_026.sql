SELECT
  MIN(ce.valuenum) AS min_resp_rate_first_24h
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS s
  ON p.subject_id = s.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON ce.subject_id = s.subject_id
  AND ce.hadm_id    = s.hadm_id
  AND ce.stay_id    = s.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 39 AND 49
  AND ce.charttime BETWEEN s.intime
                       AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  AND LOWER(di.label) LIKE '%respiratory rate%'
  AND ce.valuenum IS NOT NULL;