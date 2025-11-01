WITH stay_avg_map AS (
    SELECT
        ie.stay_id,
        AVG(ch.valuenum) AS avg_map_per_stay
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
        ON ie.stay_id = ch.stay_id
        AND ch.charttime >= ie.intime
        AND ch.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
        AND ch.itemid IN (220052, 220181, 225312)  -- MAP itemids
        AND ch.valuenum IS NOT NULL
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 89 AND 99
    GROUP BY ie.stay_id
)
SELECT
    ROUND(AVG(avg_map_per_stay), 2) AS overall_avg_map
FROM stay_avg_map;