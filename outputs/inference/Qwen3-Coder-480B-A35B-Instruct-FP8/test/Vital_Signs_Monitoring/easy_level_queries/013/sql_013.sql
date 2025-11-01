SELECT MIN(ce.valuenum) AS min_heart_rate
FROM physionet-data.mimiciv_3_1_icu.icustays AS icu
JOIN physionet-data.mimiciv_3_1_hosp.patients AS p
  ON icu.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_icu.chartevents AS ce
  ON icu.stay_id = ce.stay_id
JOIN physionet-data.mimiciv_3_1_icu.d_items AS di
  ON ce.itemid = di.itemid
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND di.label = 'Heart Rate'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= icu.intime
  AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);