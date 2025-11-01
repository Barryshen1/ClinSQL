SELECT
    MAX(ce.valuenum) AS max_respiratory_rate_first_24h
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND ce.itemid IN (
        220210, -- Respiratory Rate
        224690  -- Respiratory Rate (Total)
    )
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Filtering out potential data entry errors;