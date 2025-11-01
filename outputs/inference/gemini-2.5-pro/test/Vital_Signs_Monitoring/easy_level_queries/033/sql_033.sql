SELECT
    -- Calculate IQR as the difference between the 75th and 25th percentiles.
    -- APPROX_QUANTILES(col, 4) returns an array: [min, 25th_pctl, median, 75th_pctl, max]
    APPROX_QUANTILES(ce.valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(ce.valuenum, 4)[OFFSET(1)] AS iqr_heart_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
WHERE
    -- 1. Filter for the patient cohort: female, age 45-55
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    -- 2. Filter for heart rate measurements
    AND ce.itemid = 220045 -- Heart Rate
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 -- Basic data quality check
    -- 3. Filter for measurements on or after the start of ICU day 2
    AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);