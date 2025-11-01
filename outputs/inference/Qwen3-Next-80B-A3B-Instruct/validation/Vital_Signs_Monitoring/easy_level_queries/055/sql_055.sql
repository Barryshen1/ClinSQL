SELECT STDDEV(ce.valuenum) AS sbp_stddev
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_icu.icustays ic ON p.subject_id = ic.subject_id
JOIN physionet-data.mimiciv_3_1_icu.chartevents ce ON ic.stay_id = ce.stay_id
JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 76 AND 86
  AND (LOWER(ic.first_careunit) LIKE '%stepdown%' OR LOWER(ic.first_careunit) LIKE '%imc%')
  AND LOWER(di.label) IN ('systolic bp', 'sbp', 'arterial bp systolic', 'systolic blood pressure')
  AND ce.charttime >= ic.intime
  AND ce.charttime < ic.intime + INTERVAL 24 HOUR
  AND ce.valuenum IS NOT NULL;