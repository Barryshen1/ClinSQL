WITH TargetPatients AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81
),
-- Step 2: Identify relevant itemids for Diastolic Blood Pressure (DBP)
DiastolicBPItemIDs AS (
    SELECT
        itemid
    FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE
        -- Common itemids for Diastolic Blood Pressure (invasive and non-invasive)
        itemid IN (8440, 220059, 220180)
        -- We can also use a LIKE clause, but specific itemids are often more precise for critical vital signs.
        -- AND LOWER(label) LIKE '%diastolic blood pressure%'
        -- AND category IN ('Routine Vital Signs', 'Hemodynamics')
),
-- Step 3 & 4: Retrieve DBP measurements for target patients, and calculate max DBP per ICU stay
PerStayMaxDBP AS (
    SELECT
        icu.stay_id,
        MAX(ce.valuenum) AS max_dbp_per_stay
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ce.subject_id = icu.subject_id
        AND ce.hadm_id = icu.hadm_id
        AND ce.stay_id = icu.stay_id
    INNER JOIN
        TargetPatients tp
        ON icu.subject_id = tp.subject_id
    INNER JOIN
        DiastolicBPItemIDs dbp_items
        ON ce.itemid = dbp_items.itemid
    WHERE
        ce.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND ce.valuenum > 0     -- DBP must be positive
        AND ce.valuenum < 300   -- Filter out implausible high values which are likely errors
    GROUP BY
        icu.stay_id
)
-- Step 5: Calculate the median of these per-stay maximum DBP values
SELECT
    PERCENTILE_CONT(max_dbp_per_stay, 0.5) OVER () AS median_per_stay_max_dbp
FROM
    PerStayMaxDBP
LIMIT 1; -- LIMIT 1 because PERCENTILE_CONT with an empty OVER() returns the same value for all rows;