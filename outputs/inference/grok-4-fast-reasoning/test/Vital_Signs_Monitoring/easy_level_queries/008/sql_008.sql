SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
  ON ce.subject_id = i.subject_id
  AND ce.hadm_id = i.hadm_id
  AND ce.stay_id = i.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ce.subject_id = p.subject_id
WHERE ce.itemid = 618
  AND ce.valuenum IS NOT NULL
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62
  AND ce.charttime >= TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY);