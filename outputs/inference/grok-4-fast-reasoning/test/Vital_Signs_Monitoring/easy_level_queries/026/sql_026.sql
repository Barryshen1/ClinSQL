SELECT MIN(ce.valuenum) AS min_respiratory_rate
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON p.subject_id = ic.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON ic.subject_id = ce.subject_id
  AND ic.hadm_id = ce.hadm_id
  AND ic.stay_id = ce.stay_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 39 AND 49
  AND ce.itemid IN (618, 220210)
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= ic.intime
  AND ce.charttime < ic.intime + INTERVAL 24 HOUR;