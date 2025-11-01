SELECT
    MAX(ce.valuenum) AS max_respiratory_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND di.label LIKE '%Respiratory Rate%' -- Catches various types of respiratory rate measurements
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= TIMESTAMP_ADD(icu.intime, INTERVAL 1 DAY) -- Filter for ICU day 2 or later;