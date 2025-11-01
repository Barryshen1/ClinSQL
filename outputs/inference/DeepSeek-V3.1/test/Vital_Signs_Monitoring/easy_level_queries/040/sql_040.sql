WITH first_map AS (
    SELECT 
        ie.stay_id,
        ce.valuenum AS first_map
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 55 AND 65
        AND ce.itemid = 220181  -- MAP measurement
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ie.intime
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 1 HOUR)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
    STDDEV(fm.first_map) AS sd_first_map
FROM first_map fm;