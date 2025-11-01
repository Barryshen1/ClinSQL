SELECT STDDEV(ce.valuenum) AS sbp_stddev
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 76 AND 86
  AND LOWER(icu.first_careunit) LIKE '%step%'
    OR LOWER(icu.first_careunit) LIKE '%imc%'
  AND ce.charttime >= icu.intime
  AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND LOWER(di.label) = 'nibp systolic'
  AND ce.valuenum IS NOT NULL;