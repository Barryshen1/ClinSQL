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
  AND ic.intime IS NOT NULL
  AND ce.itemid IN (220210, 223835)
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum BETWEEN 0 AND 100
  AND ce.charttime >= ic.intime
  AND TIMESTAMP_DIFF(ce.charttime, ic.intime, HOUR) <= 24;