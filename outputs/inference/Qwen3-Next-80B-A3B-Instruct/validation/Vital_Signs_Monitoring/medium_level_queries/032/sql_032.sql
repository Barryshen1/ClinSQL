SELECT STDDEV(ce.valuenum) AS nighttime_sbp_stddev
FROM physionet-data.mimiciv_3_1_hosp.patients p
INNER JOIN physionet-data.mimiciv_3_1_icu.icustays ic ON p.subject_id = ic.subject_id
INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce ON ic.stay_id = ce.stay_id
INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di_sb ON ce.itemid = di_sb.itemid
INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe ON ic.stay_id = pe.stay_id
INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di_vent ON pe.itemid = di_vent.itemid
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 53 AND 63
  AND (
    LOWER(ic.first_careunit) LIKE '%step down%'
    OR LOWER(ic.first_careunit) LIKE '%imc%'
    OR LOWER(ic.first_careunit) LIKE '%intermediate care%'
    OR LOWER(ic.last_careunit) LIKE '%step down%'
    OR LOWER(ic.last_careunit) LIKE '%imc%'
    OR LOWER(ic.last_careunit) LIKE '%intermediate care%'
  )
  AND LOWER(di_vent.label) LIKE '%invasive%ventilation%'
  AND LOWER(di_sb.label) LIKE '%systolic%bp%'
  AND LOWER(di_sb.label) LIKE '%sbp%'
  AND ce.valuenum IS NOT NULL
  AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5;