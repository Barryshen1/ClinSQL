WITH AvgMapPerStayCTE AS (
    -- Step 2: Calculate per-stay average MAP for the cohort
    SELECT
        c.stay_id,
        AVG(ce.valuenum) AS avg_map_per_stay
    FROM
        (
            -- Step 1: Define the target cohort (male, age 38-48, with an ICU stay)
            SELECT
                p.subject_id,
                ics.stay_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.patients` p
            INNER JOIN
                `physionet-data.mimiciv_3_1_icu.icustays` ics
                ON p.subject_id = ics.subject_id
            WHERE
                p.gender = 'M'
                AND p.anchor_age BETWEEN 38 AND 48
        ) c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220052, -- Arterial Blood Pressure mean (invasive)
            220181, -- Non Invasive Blood Pressure mean
            224368, -- MAP (Arterial)
            224673  -- MAP (Non-Invasive)
        )
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum >= 20 -- Physiologically reasonable lower limit for MAP
        AND ce.valuenum <= 250 -- Physiologically reasonable upper limit for MAP
    GROUP BY
        c.stay_id
)
-- Final step: Calculate percentile rank based on the average MAPs
SELECT
    COUNT(psm.avg_map_per_stay) AS total_stays_in_cohort_with_map,
    -- Count the number of stays where the average MAP is less than or equal to 60 mmHg
    COUNTIF(psm.avg_map_per_stay <= 60) AS stays_with_avg_map_le_60,
    -- Calculate the percentile rank as the proportion of stays with avg_map <= 60 mmHg
    (COUNTIF(psm.avg_map_per_stay <= 60) * 100.0) / COUNT(psm.avg_map_per_stay) AS percentile_rank_at_60_mmhg
FROM
    AvgMapPerStayCTE psm
WHERE
    psm.avg_map_per_stay IS NOT NULL; -- Ensure we only consider stays with a valid average MAP;