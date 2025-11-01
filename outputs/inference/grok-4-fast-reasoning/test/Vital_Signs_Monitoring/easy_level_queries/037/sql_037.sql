SELECT
  AVG(ce.valuenum) AS average_map
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` i
ON
  p.subject_id = i.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
ON
  i.subject_id = ce.subject_id
  AND i.hadm_id = ce.hadm_id
  AND i.stay_id = ce.stay_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 89 AND 99
  AND ce.itemid = 220052
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= i.intime
  AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR);