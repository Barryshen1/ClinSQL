WITH per_stay_avg_hr AS (
    SELECT 
        ce.stay_id,
        AVG(ce.valuenum) AS mean_heart_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE 
        ce.itemid = 220045  -- Heart Rate
        AND ce.valuenum IS NOT NULL
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
    GROUP BY ce.stay_id
)
SELECT 
    PERCENTILE_CONT(mean_heart_rate, 0.5) OVER() AS median_per_stay_mean_hr
FROM per_stay_avg_hr
LIMIT 1;