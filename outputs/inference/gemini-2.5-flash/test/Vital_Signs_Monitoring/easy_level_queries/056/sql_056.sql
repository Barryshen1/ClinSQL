SELECT
    APPROX_QUANTILES(ce.valuenum, 2)[OFFSET(1)] AS median_temperature_f
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND ce.itemid = 223761 -- itemid for Temperature F
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);