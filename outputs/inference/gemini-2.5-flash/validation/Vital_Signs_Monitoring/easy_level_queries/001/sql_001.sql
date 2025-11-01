WITH PatientCohort AS (
    -- Select subject_ids, hadm_ids, and stay_ids for male ICU patients aged 52-62
    SELECT
        p.subject_id,
        ics.hadm_id,
        ics.stay_id,
        p.anchor_age -- Included for clarity, though already filtered
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS ics
        ON p.subject_id = ics.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62 -- Filter for the specified age range
),
MAP_Measurements AS (
    -- Retrieve all valid MAP measurements for the identified patient cohort
    SELECT
        pc.stay_id,
        ce.charttime,
        ce.valuenum,
        ce.itemid -- Include itemid for robust tie-breaking in ordering
    FROM
        PatientCohort AS pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON pc.subject_id = ce.subject_id
        AND pc.hadm_id = ce.hadm_id
        AND pc.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220052, -- Arterial Blood Pressure mean (invasive)
            220181  -- Non Invasive Blood Pressure mean
        )
        AND ce.valuenum IS NOT NULL -- Exclude rows where MAP value is missing
        AND ce.valuenum > 0     -- Exclude non-positive or erroneous MAP values
),
FirstMAP AS (
    -- Identify the first recorded MAP value for each unique ICU stay
    SELECT
        stay_id,
        valuenum AS first_map_value
    FROM (
        SELECT
            stay_id,
            valuenum,
            ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime ASC, itemid ASC, valuenum ASC) AS rn
        FROM
            MAP_Measurements
    )
    WHERE
        rn = 1 -- Select only the first recorded MAP value per ICU stay
)
-- Calculate the Interquartile Range (IQR) of the first MAP values
SELECT
    (PERCENTILE_CONT(first_map_value, 0.75) OVER()) - (PERCENTILE_CONT(first_map_value, 0.25) OVER()) AS iqr_first_map
FROM
    FirstMAP
LIMIT 1; -- The result is a single aggregate value;