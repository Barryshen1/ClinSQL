WITH cohort AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS avg_map
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 93
        AND ce.itemid = 220181  -- MAP itemid
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ie.intime
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
    GROUP BY ie.stay_id
    HAVING COUNT(ce.valuenum) >= 3  -- At least 3 measurements
),
percentiles AS (
    SELECT
        avg_map,
        PERCENT_RANK() OVER (ORDER BY avg_map) AS percentile_rank
    FROM cohort
)
SELECT 
    percentile_rank * 100 AS percentile
FROM percentiles
WHERE avg_map = 60.0;