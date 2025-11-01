WITH first_map AS (
    SELECT 
        c.stay_id,
        c.valuenum,
        ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
    WHERE 
        p.gender = 'M'
        AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 55 AND 65
        AND d.label = 'MAP'
        AND c.charttime >= i.intime
)
SELECT 
    STDDEV(valuenum) AS sd_first_map
FROM first_map
WHERE rn = 1;