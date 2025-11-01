SELECT MAX(ce.valuenum) AS max_resp_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON i.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON i.stay_id = ce.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE p.gender = 'M'
  AND (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 52 AND 62
  AND ce.charttime >= i.intime + INTERVAL 1 DAY
  AND LOWER(di.label) LIKE '%respiratory rate%'
  AND ce.valuenum IS NOT NULL;