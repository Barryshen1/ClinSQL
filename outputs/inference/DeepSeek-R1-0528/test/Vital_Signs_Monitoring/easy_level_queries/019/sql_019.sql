WITH step_down_stays AS (
    SELECT 
        t.transfer_id,
        t.subject_id,
        t.hadm_id,
        t.intime,
        t.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON t.subject_id = p.subject_id
    WHERE 
        t.careunit IN ('Step-Down', 'Intermediate Care')
        AND t.eventtype IN ('admit', 'transfer')
        AND p.gender = 'F'
        AND EXTRACT(YEAR FROM t.intime) - p.anchor_year + p.anchor_age BETWEEN 73 AND 83
),
map_events AS (
    SELECT 
        s.transfer_id,
        c.valuenum AS map_value
    FROM step_down_stays s
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON s.subject_id = c.subject_id
        AND s.hadm_id = c.hadm_id
        AND c.charttime BETWEEN s.intime AND s.outtime
        AND c.itemid IN (220052, 220181)  -- MAP item IDs
        AND c.valuenum IS NOT NULL
),
per_stay_avg AS (
    SELECT 
        transfer_id,
        AVG(map_value) AS avg_map_per_stay
    FROM map_events
    GROUP BY transfer_id
)
SELECT 
    AVG(avg_map_per_stay) AS overall_avg_map
FROM per_stay_avg;