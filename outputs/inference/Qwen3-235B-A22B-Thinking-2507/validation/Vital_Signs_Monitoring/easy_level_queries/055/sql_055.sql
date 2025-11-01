SELECT STDDEV(ce.valuenum) AS sbp_stddev
FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ie.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON ie.stay_id = ce.stay_id
WHERE
  p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 76 AND 86
  AND ce.itemid IN (220050, 220179, 225309)
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.charttime >= ie.intime
  AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR);