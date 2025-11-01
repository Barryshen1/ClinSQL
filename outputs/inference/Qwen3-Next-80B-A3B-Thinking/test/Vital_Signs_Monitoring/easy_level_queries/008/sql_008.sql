SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62
  AND ce.itemid = 220210
  AND ce.charttime >= icu.intime + INTERVAL '24' HOUR
  AND ce.valuenum IS NOT NULL;