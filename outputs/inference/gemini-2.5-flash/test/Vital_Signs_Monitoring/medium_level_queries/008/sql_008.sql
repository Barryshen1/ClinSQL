WITH Target_Population AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
),
MAP_Measurements_24hr AS (
    SELECT
        tp.stay_id,
        ce.valuenum
    FROM
        Target_Population tp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tp.subject_id = ce.subject_id
        AND tp.hadm_id = ce.hadm_id
        AND tp.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220052 -- itemid for 'Arterial Blood Pressure mean' (MAP)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Exclude nulls and non-physiological zero values
        AND ce.charttime BETWEEN tp.intime AND DATETIME_ADD(tp.intime, INTERVAL 24 HOUR)
),
Average_MAP_Per_Stay AS (
    SELECT
        stay_id,
        AVG(valuenum) AS avg_map_24hr
    FROM
        MAP_Measurements_24hr
    GROUP BY
        stay_id
    HAVING
        COUNT(valuenum) > 0 -- Ensure at least one valid MAP measurement was recorded
),
Percentile_Calculation_Data AS (
    SELECT
        -- Count how many stays have an average MAP <= 75 mmHg
        COUNT(CASE WHEN avg_map_24hr <= 75 THEN 1 END) AS count_le_75,
        -- Count the total number of stays that meet all criteria and have an average MAP
        COUNT(avg_map_24hr) AS total_stays_with_avg_map
    FROM
        Average_MAP_Per_Stay
)
SELECT
    -- Calculate the percentile rank: (number of values <= 75 / total values) * 100
    -- SAFE_DIVIDE handles potential division by zero if total_stays_with_avg_map is 0.
    SAFE_DIVIDE(
        CAST(pc.count_le_75 AS BIGNUMERIC),
        CAST(pc.total_stays_with_avg_map AS BIGNUMERIC)
    ) * 100 AS percentile_75_mmHg_for_target_population
FROM
    Percentile_Calculation_Data pc;