SELECT
    MAX(ce.valuenum) AS max_respiratory_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: males aged 52-62
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62

    -- 2. Filter for respiratory rate measurements using their itemids
    AND ce.itemid IN (
        220210, -- Respiratory Rate
        224690  -- Respiratory Rate (Total)
    )

    -- 3. Filter for measurements taken on or after ICU day 2
    -- (i.e., at least 24 hours after ICU admission)
    AND DATETIME_DIFF(ce.charttime, icu.intime, HOUR) >= 24

    -- 4. Apply a sanity check to exclude nulls and likely data errors
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300;