SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icu.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON icu.stay_id = ce.stay_id
WHERE 
  pat.gender = 'F'
  AND (DATE_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1), YEAR) + pat.anchor_age) BETWEEN 38 AND 48
  AND ce.itemid IN (220210, 224688, 224689, 224690)  -- Respiratory Rate item IDs
  AND ce.charttime >= icu.intime
  AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL;