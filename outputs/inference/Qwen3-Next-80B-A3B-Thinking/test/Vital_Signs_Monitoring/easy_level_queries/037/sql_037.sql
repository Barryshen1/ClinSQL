SELECT AVG(ce.valuenum) AS avg_map
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ce.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
WHERE di.label = 'MAP'
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 89 AND 99
  AND ce.charttime >= icu.intime
  AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL;