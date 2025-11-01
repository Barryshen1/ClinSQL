SELECT MIN(ce.valuenum) AS min_resp_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON icu.stay_id = ce.stay_id
WHERE p.gender = 'M'
  AND ce.itemid IN (220210, 224690)  -- Standard respiratory rate itemids
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= icu.intime
  AND ce.charttime <= icu.intime + INTERVAL '24' HOUR
  AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 39 AND 49;