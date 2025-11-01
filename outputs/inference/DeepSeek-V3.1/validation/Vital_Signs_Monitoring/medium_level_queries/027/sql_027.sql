WITH hr_avg AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS avg_hr
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 80 AND 90
        AND ce.itemid = 220045  -- Heart Rate
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
    GROUP BY ie.stay_id
)
SELECT 
    PERCENT_RANK() OVER (ORDER BY avg_hr) * 100 AS percentile
FROM hr_avg
WHERE avg_hr = 110;