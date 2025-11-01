WITH stay_max_map AS (
    SELECT 
        ie.stay_id,
        MAX(ce.valuenum) AS max_map
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
        AND ce.itemid IN (220181, 225312)  -- MAP itemids (non-invasive and arterial)
        AND ce.valuenum IS NOT NULL
    GROUP BY ie.stay_id
)
SELECT 
    AVG(max_map) AS avg_max_map
FROM stay_max_map;