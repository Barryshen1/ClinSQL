WITH cohort_stays AS (
    SELECT 
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 38 AND 48
),

sbp_events AS (
    SELECT 
        c.stay_id,
        ce.valuenum AS sbp
    FROM cohort_stays c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE 
        ce.itemid IN (220179, 225309)  -- SBP item IDs
        AND ce.valuenum IS NOT NULL    -- Ensure numeric values
        AND ce.charttime >= c.intime
        AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

avg_sbp_per_stay AS (
    SELECT 
        stay_id,
        AVG(sbp) AS avg_sbp
    FROM sbp_events
    GROUP BY stay_id
)

SELECT 
    (COUNTIF(avg_sbp <= 130) * 100.0) / COUNT(*) AS percentile_130
FROM avg_sbp_per_stay;