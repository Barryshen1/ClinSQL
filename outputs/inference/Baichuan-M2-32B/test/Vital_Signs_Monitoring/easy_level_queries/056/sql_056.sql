WITH temp_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'Vital Signs'
      AND label LIKE '%Temperature%'
      AND unitname = '°F'
),
cohort AS (
    SELECT p.subject_id, p.gender, p.anchor_age, i.hadm_id, i.stay_id, i.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON p.subject_id = i.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 46 AND 56
),
temp_readings AS (
    SELECT c.subject_id, c.stay_id, ce.charttime, ce.valuenum
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
      AND c.hadm_id = ce.hadm_id
      AND c.stay_id = ce.stay_id
    WHERE ce.itemid IN (SELECT itemid FROM temp_itemids)
      AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 24 HOUR
      AND ce.valuenum BETWEEN 95 AND 106  -- reasonable range for human body temperature in °F
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_temp_f
FROM temp_readings;