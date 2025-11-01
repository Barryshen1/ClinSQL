SELECT
    AVG(ce.valuenum) AS average_map
FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
WHERE
    p.gender = 'F' -- Filter for female patients
    AND p.anchor_age BETWEEN 89 AND 99 -- Filter for age between 89 and 99 (inclusive)
    AND ce.itemid IN (220052, 224685) -- ItemIDs for Mean Arterial Pressure (ABP Mean, NBP Mean)
    AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
    AND ce.valuenum > 0 -- Exclude zero or negative values often indicative of bad data
    AND ce.valuenum BETWEEN 40 AND 180 -- Filter for physiologically plausible MAP values (e.g., 40-180 mmHg)
    AND ce.charttime >= icu.intime -- Measurement taken after ICU admission
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR) -- Measurement taken within the first 24 hours of ICU stay;