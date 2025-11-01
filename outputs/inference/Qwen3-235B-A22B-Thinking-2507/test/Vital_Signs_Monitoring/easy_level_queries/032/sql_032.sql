SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON icu.stay_id = ce.stay_id
WHERE 
  p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 38 AND 48
  AND ce.charttime >= icu.intime
  AND ce.charttime <= icu.intime + INTERVAL 24 HOUR
  AND ce.itemid IN (220210, 224690)
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0;