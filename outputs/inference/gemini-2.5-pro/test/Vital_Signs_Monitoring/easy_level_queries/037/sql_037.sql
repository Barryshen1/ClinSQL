SELECT
    ROUND(AVG(ce.valuenum), 2) AS average_map_first_24h
FROM
    physionet-data.mimiciv_3_1_hosp.patients AS p
JOIN
    physionet-data.mimiciv_3_1_icu.icustays AS icu
    ON p.subject_id = icu.subject_id
JOIN
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: female, aged 89-99 at ICU admission
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age BETWEEN 89 AND 99

    -- 2. Filter for MAP measurements (both invasive and non-invasive)
    AND ce.itemid IN (
        220052, -- Arterial Blood Pressure mean
        220181, -- Non Invasive Blood Pressure mean
        225312  -- ART BP mean
    )

    -- 3. Filter for the first 24 hours of the ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)

    -- 4. Ensure data quality
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0;