SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM physionet-data.mimiciv_3_1_icu.chartevents ce
JOIN physionet-data.mimiciv_3_1_icu.icustays icu ON ce.stay_id = icu.stay_id
JOIN physionet-data.mimiciv_3_1_hosp.patients p ON icu.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
WHERE LOWER(di.label) = 'respiratory rate'
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62
  AND ce.charttime >= icu.intime + INTERVAL '48' HOUR
  AND ce.valuenum IS NOT NULL;