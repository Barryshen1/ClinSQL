SELECT
    MIN(ce.valuenum) AS min_respiratory_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: Males aged 39-49
    p.gender = 'M'
    AND p.anchor_age >= 39
    AND p.anchor_age <= 49

    -- 2. Filter for Respiratory Rate measurements
    AND ce.itemid IN (
        220210, -- Respiratory Rate
        224690  -- Respiratory Rate (Total)
    )

    -- 3. Filter for measurements within the first 24 hours of the ICU stay
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)

    -- 4. Filter for valid, physiological values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0;