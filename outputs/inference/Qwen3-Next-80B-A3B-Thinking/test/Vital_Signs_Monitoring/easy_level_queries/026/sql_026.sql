SELECT MIN(ce.valuenum) AS min_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ce.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 39 AND 49
  AND di.label = 'Respiratory Rate'
  AND ce.charttime >= icu.intime
  AND ce.charttime <= icu.intime + INTERVAL 24 HOUR
  AND ce.valuenum IS NOT NULL;