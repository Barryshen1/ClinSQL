SELECT MAX(ce.valuenum) AS max_resp_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
  ON ce.itemid = di.itemid
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
  ON ce.stay_id = ie.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON ie.subject_id = p.subject_id
WHERE di.label = 'Respiratory Rate'
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR);