SELECT
    MAX(ce.valuenum) AS max_respiratory_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.itemid IN (220210, 618, 224690) -- Common ItemIDs for 'Respiratory Rate'
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0;