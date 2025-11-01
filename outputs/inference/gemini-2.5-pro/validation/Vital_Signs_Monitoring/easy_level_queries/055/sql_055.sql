SELECT
    STDDEV_SAMP(ce.valuenum) AS sbp_stddev_first_24hr
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    ON p.subject_id = ie.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ie.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: Males aged 76-86
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86

    -- 2. Filter for stays that began in a step-down/intermediate care unit
    AND ie.first_careunit LIKE '%Intermediate%'

    -- 3. Filter for Systolic Blood Pressure (SBP) measurements (invasive and non-invasive)
    AND ce.itemid IN (
        220179, -- Non Invasive Blood Pressure systolic
        220050, -- Arterial Blood Pressure systolic
        225309  -- ART BP Systolic
    )

    -- 4. Filter for measurements taken within the first 24 hours of the ICU stay
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)

    -- 5. Filter for plausible SBP values to exclude errors
    AND ce.valuenum > 0 AND ce.valuenum < 300;