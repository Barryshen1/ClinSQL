SELECT MIN(ce.valuenum) AS min_respiratory_rate
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 39 AND 49
  AND ce.charttime >= icu.intime
  AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND LOWER(di.label) = 'respiratory rate'
  AND ce.valuenum IS NOT NULL;