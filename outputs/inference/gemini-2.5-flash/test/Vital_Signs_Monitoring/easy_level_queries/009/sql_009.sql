WITH TargetPatients AS (
    -- Step 1: Identify female patients aged 86-96
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 86 AND 96
),
ICUStaysFiltered AS (
    -- Step 2: Get ICU stay start times for these patients
    SELECT
        tpa.subject_id,
        ics.hadm_id,
        ics.stay_id,
        ics.intime
    FROM
        TargetPatients tpa
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ics
        ON tpa.subject_id = ics.subject_id
),
RawTemperatureEvents AS (
    -- Step 3 & 4: Retrieve temperature measurements within the first 24 hours
    -- Filter by d_items label and category, and ensure valuenum is not NULL
    SELECT
        isf.subject_id,
        isf.hadm_id,
        isf.stay_id,
        ce.charttime,
        ce.valuenum,
        di.label AS item_label
    FROM
        ICUStaysFiltered isf
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON isf.subject_id = ce.subject_id
            AND isf.hadm_id = ce.hadm_id
            AND isf.stay_id = ce.stay_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
            ON ce.itemid = di.itemid
    WHERE
        ce.valuenum IS NOT NULL
        AND di.category = 'Routine Vital Signs' -- Focus on vital sign temperature items
        AND (
                LOWER(di.label) LIKE '%temperature f%'
            OR  LOWER(di.label) LIKE '%temperature c%'
        )
        AND ce.charttime >= isf.intime
        AND ce.charttime <= DATETIME_ADD(isf.intime, INTERVAL 24 HOUR)
),
ProcessedTemperatures AS (
    -- Step 5: Convert temperatures to Fahrenheit and apply physiological range filter
    SELECT
        CASE
            WHEN LOWER(rte.item_label) LIKE '%temperature c%' THEN (rte.valuenum * 9/5) + 32
            ELSE rte.valuenum -- Assume it's already Fahrenheit if not specified as Celsius
        END AS temperature_f
    FROM
        RawTemperatureEvents rte
    WHERE
        -- Filter out physiologically implausible temperature values regardless of original unit
        -- Convert to Celsius for a consistent range check (15C to 45C roughly covers 59F to 113F)
        CASE
            WHEN LOWER(rte.item_label) LIKE '%temperature c%' THEN rte.valuenum BETWEEN 15.0 AND 45.0
            WHEN LOWER(rte.item_label) LIKE '%temperature f%' THEN (rte.valuenum - 32) * 5/9 BETWEEN 15.0 AND 45.0
            ELSE FALSE -- Exclude any other unexpected labels if they exist
        END
)
-- Step 6: Calculate the 75th percentile of all valid Fahrenheit temperatures
SELECT
    PERCENTILE_CONT(temperature_f, 0.75) OVER() AS temperature_75th_percentile_f
FROM
    ProcessedTemperatures
WHERE temperature_f IS NOT NULL; -- Ensure no NULLs before percentile calculation;