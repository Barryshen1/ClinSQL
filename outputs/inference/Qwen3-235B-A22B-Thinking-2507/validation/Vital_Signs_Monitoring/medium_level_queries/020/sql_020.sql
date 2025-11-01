WITH cohort AS (
    SELECT 
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    WHERE pat.gender = 'F'
        AND (EXTRACT(YEAR FROM icu.intime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 58 AND 68
),
map_data AS (
    SELECT 
        c.stay_id,
        AVG(ce.valuenum) AS mean_map
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220052
        AND ce.charttime >= c.intime
        AND ce.charttime <= c.intime + INTERVAL '48' HOUR
        AND ce.valuenum IS NOT NULL
    GROUP BY c.stay_id
)
SELECT 
    (COUNTIF(mean_map <= 85) * 100.0) / COUNT(*) AS percentile
FROM map_data;