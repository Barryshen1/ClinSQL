SELECT
  p.subject_id,
  isty.hadm_id,
  MIN(ce.valuenum) AS min_hr_within_24h
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS isty
  ON p.subject_id = isty.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON ce.subject_id = isty.subject_id
  AND ce.hadm_id = isty.hadm_id
  AND ce.stay_id = isty.stay_id
JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND di.label LIKE '%Heart rate%'
  AND ce.charttime >= isty.intime
  AND ce.charttime < TIMESTAMP_ADD(isty.intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL
GROUP BY p.subject_id, isty.hadm_id
HAVING MIN(ce.valuenum) IS NOT NULL
ORDER BY min_hr_within_24h ASC;