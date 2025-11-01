WITH cohort AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS avg_heart_rate,
        PERCENT_RANK() OVER (ORDER BY AVG(ce.valuenum)) AS percentile_rank
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 42 AND 52
        AND ce.itemid = 220045  -- Heart rate
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- Valid heart rate values
    GROUP BY ie.stay_id
)
SELECT 
    COUNT(*) AS cohort_size,
    percentile_rank * 100 AS percentile
FROM cohort
WHERE avg_heart_rate = 90;