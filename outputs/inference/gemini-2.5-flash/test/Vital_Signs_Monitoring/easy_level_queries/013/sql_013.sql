SELECT
    MIN(ce.valuenum) AS min_heart_rate_in_first_24h
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
WHERE
    p.gender = 'F' -- Filter for female patients
    AND p.anchor_age BETWEEN 44 AND 54 -- Filter for age range 44-54
    AND ce.itemid = 220045 -- ItemID for 'Heart Rate' from d_items
    AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists for heart rate
    AND ce.valuenum > 0 -- Heart rate must be a positive value
    AND ce.charttime >= icu.intime -- Event occurred after ICU admission
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR) -- Event occurred within the first 24 hours of ICU stay;