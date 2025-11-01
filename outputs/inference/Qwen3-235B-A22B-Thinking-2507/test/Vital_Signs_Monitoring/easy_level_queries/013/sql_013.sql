SELECT MIN(ce.valuenum) AS min_heart_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON icu.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON icu.stay_id = ce.stay_id
WHERE p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 44 AND 54
  AND ce.itemid = 220045
  AND ce.charttime >= icu.intime
  AND ce.charttime < icu.intime + INTERVAL '24' HOUR
  AND ce.valuenum IS NOT NULL;