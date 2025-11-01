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
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
),
map_first_24h AS (
    SELECT 
        c.stay_id,
        AVG(ce.valuenum) AS avg_map
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220181  -- MAP
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY c.stay_id
),
all_avg_maps AS (
    SELECT 
        stay_id,
        avg_map,
        PERCENT_RANK() OVER (ORDER BY avg_map) AS percentile_rank
    FROM map_first_24h
)
SELECT 
    percentile_rank
FROM all_avg_maps
WHERE avg_map = 75.0
LIMIT 1;