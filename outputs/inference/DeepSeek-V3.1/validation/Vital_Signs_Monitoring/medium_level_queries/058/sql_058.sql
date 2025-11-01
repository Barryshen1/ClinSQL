WITH cohort AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS avg_sbp
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND ce.itemid = 220179  -- Systolic BP
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- exclude erroneous values
        AND ce.charttime >= ie.intime
        AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    GROUP BY ie.stay_id
    HAVING avg_sbp IS NOT NULL
),
percentiles AS (
    SELECT
        avg_sbp,
        PERCENT_RANK() OVER (ORDER BY avg_sbp) AS percentile_rank
    FROM cohort
)
SELECT 
    percentile_rank
FROM percentiles
WHERE avg_sbp = 120
LIMIT 1;