WITH first_map_per_stay AS (
    SELECT
        -- Use ROW_NUMBER to find the first measurement for each ICU stay
        ce.valuenum,
        ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON icu.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON icu.stay_id = ce.stay_id
    WHERE
        -- 1. Filter for the patient cohort: Male, age 52-62
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        -- 2. Filter for MAP measurements (invasive and non-invasive)
        AND ce.itemid IN (
            220052, -- Arterial Blood Pressure mean
            225312, -- Inv-ABP Mean
            220181  -- Non Invasive Blood Pressure mean
        )
        -- 3. Filter for valid, plausible numeric values
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 AND ce.valuenum < 300
)

-- Final step: Calculate IQR from the first MAP values
SELECT
    -- Calculate IQR = 75th percentile (Q3) - 25th percentile (Q1)
    -- APPROX_QUANTILES(value, 4) returns an array: [min, Q1, median, Q3, max]
    -- The OFFSET is 0-indexed, so Q1 is at OFFSET(1) and Q3 is at OFFSET(3).
    APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS map_iqr
FROM
    first_map_per_stay
WHERE
    -- Select only the first measurement (ranked #1) for each stay
    rn = 1;