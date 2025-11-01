SELECT
    MIN(ce.valuenum) AS min_heart_rate_first_24h
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: females aged 44-54
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54

    -- 2. Filter for the specific measurement: Heart Rate
    AND ce.itemid = 220045 -- Heart Rate

    -- 3. Filter for the time window: first 24 hours of the ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)

    -- 4. Basic data cleaning: exclude non-physiological values
    AND ce.valuenum > 0;