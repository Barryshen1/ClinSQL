SELECT
    MIN(ce.valuenum) AS min_respiratory_rate_first_24h
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ce.itemid = 220210 -- Itemid for 'Respiratory Rate' from d_items
    AND ce.valuenum IS NOT NULL -- Exclude records without a numeric value
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
;