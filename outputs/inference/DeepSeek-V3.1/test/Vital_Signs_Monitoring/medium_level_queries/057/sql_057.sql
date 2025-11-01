WITH cohort_stays AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 85 AND 95
),

temp_measurements AS (
    SELECT 
        ce.stay_id,
        ce.valuenum AS temp_c
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid = 223762  -- Temperature Celsius
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 30 AND 45  -- plausible range
),

per_stay_avg AS (
    SELECT 
        cs.stay_id,
        AVG(tm.temp_c) AS avg_temp
    FROM cohort_stays cs
    INNER JOIN temp_measurements tm
        ON cs.stay_id = tm.stay_id
    GROUP BY cs.stay_id
)

SELECT 
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_temp < 36.0 THEN 1 ELSE 0 END) AS count_below,
    SAFE_DIVIDE(SUM(CASE WHEN avg_temp < 36.0 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_rank
FROM per_stay_avg;