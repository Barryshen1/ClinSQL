WITH population AS (
    SELECT 
        s.stay_id,
        s.hadm_id,
        s.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` s
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON s.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 81 AND 91
),
temp_data AS (
    SELECT 
        s.stay_id,
        AVG(c.valuenum) as mean_temp
    FROM population s
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
        ON s.stay_id = c.stay_id
    WHERE c.itemid = 223762   -- Temperature Celsius
        AND c.charttime >= s.intime
        AND c.charttime < DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
        AND c.valuenum IS NOT NULL
    GROUP BY s.stay_id
),
mi_data AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'
),
combined AS (
    SELECT 
        p.stay_id,
        p.hadm_id,
        t.mean_temp,
        CASE 
            WHEN t.mean_temp < 36.0 THEN '<36.0'
            WHEN t.mean_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
            WHEN t.mean_temp >= 38.0 THEN '>=38.0'
        END as temp_class,
        IF(m.hadm_id IS NOT NULL, 1, 0) as has_mi
    FROM population p
    INNER JOIN temp_data t
        ON p.stay_id = t.stay_id
    LEFT JOIN mi_data m
        ON p.hadm_id = m.hadm_id
)
SELECT 
    temp_class,
    COUNT(*) as N,
    AVG(mean_temp) as mean_temp,
    APPROX_QUANTILES(mean_temp, 1000)[OFFSET(500)] as median_temp,
    APPROX_QUANTILES(mean_temp, 1000)[OFFSET(750)] - APPROX_QUANTILES(mean_temp, 1000)[OFFSET(250)] as iqr_temp,
    SUM(has_mi) * 100.0 / COUNT(*) as mi_rate_percent
FROM combined
GROUP BY temp_class
ORDER BY 
    CASE temp_class
        WHEN '<36.0' THEN 1
        WHEN '36.0-37.9' THEN 2
        WHEN '>=38.0' THEN 3
    END;