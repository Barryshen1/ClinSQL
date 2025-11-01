WITH avg_temps AS (
    SELECT 
        c.stay_id,
        AVG(c.valuenum) AS avg_temp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON c.itemid = d.itemid
    WHERE 
        LOWER(d.label) LIKE '%temperature%' 
        AND d.unitname = 'C'
        AND c.valuenum IS NOT NULL
    GROUP BY c.stay_id
),
target_stays AS (
    SELECT 
        a.avg_temp
    FROM avg_temps a
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 85 AND 95
)
SELECT 
    (COUNT(CASE WHEN avg_temp <= 36.0 THEN 1 END) * 100.0) / NULLIF(COUNT(*), 0) AS percentile_rank
FROM target_stays;