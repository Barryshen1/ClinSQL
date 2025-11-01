WITH FilteredPatients AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 35 AND 45
),
-- Step 2: Get all respiratory rate measurements for these patients during their ICU stays
ICUStayRespiratoryRates AS (
    SELECT
        icu.stay_id,
        ce.valuenum AS respiratory_rate_value
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        FilteredPatients fp
        ON icu.subject_id = fp.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220210 -- Itemid for 'Respiratory Rate' from d_items
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Ensure positive respiratory rate
        AND ce.valuenum < 100 -- Filter out highly improbable values (e.g., data errors)
),
-- Step 3: Calculate the maximum respiratory rate for each qualifying ICU stay
MaxRespiratoryRatePerStay AS (
    SELECT
        stay_id,
        MAX(respiratory_rate_value) AS max_rr
    FROM
        ICUStayRespiratoryRates
    GROUP BY
        stay_id
)
-- Step 4: Find the minimum of these maximum respiratory rates
SELECT
    MIN(max_rr) AS min_of_max_respiratory_rate
FROM
    MaxRespiratoryRatePerStay;