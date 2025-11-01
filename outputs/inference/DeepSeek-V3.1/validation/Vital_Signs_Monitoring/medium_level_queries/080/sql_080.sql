WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 56 AND 66
), map_data AS (
    SELECT 
        c.stay_id,
        c.subject_id,
        c.hadm_id,
        ce.valuenum AS map_value
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220181  -- MAP directly measured
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
), stay_mean_map AS (
    SELECT
        stay_id,
        AVG(map_value) AS mean_map
    FROM map_data
    GROUP BY stay_id
), categorized AS (
    SELECT
        stay_id,
        mean_map,
        CASE
            WHEN mean_map < 65 THEN '<65'
            WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
            WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
            ELSE '>=85'
        END AS map_category
    FROM stay_mean_map
)
SELECT
    map_category,
    COUNT(stay_id) AS stay_count,
    AVG(mean_map) AS mean_mean_map,
    APPROX_QUANTILES(mean_map, 2)[OFFSET(1)] AS median_mean_map,
    APPROX_QUANTILES(mean_map, 4)[OFFSET(1)] AS q1_mean_map,
    APPROX_QUANTILES(mean_map, 4)[OFFSET(3)] AS q3_mean_map
FROM categorized
GROUP BY map_category
ORDER BY map_category;