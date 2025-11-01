WITH max_map_per_stay AS (
    SELECT
        stay_id,
        MAX(ce.valuenum) AS max_map
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid IN (
            220052, -- Arterial Blood Pressure mean
            220181, -- Non Invasive Blood Pressure mean
            225312  -- Invasive Blood Pressure mean
        )
        -- Filter for plausible physiological values to exclude data entry errors
        AND ce.valuenum > 0
        AND ce.valuenum < 300
    GROUP BY
        stay_id
)

-- Step 2: Join with patient and ICU data, filter for the target cohort, and calculate the final average.
SELECT
    AVG(m.max_map) AS average_of_max_map
FROM
    max_map_per_stay AS m
-- Join to link stay_id with subject_id
JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON m.stay_id = icu.stay_id
-- Join to get patient demographics (age and gender)
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
WHERE
    -- Filter for male patients
    p.gender = 'M'
    -- Filter for patients aged between 48 and 58 (inclusive) at the time of their anchor year
    AND p.anchor_age BETWEEN 48 AND 58;