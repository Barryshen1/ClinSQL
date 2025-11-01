WITH cohort AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id, 
        ie.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 45 AND 55
),
sbp_events AS (
    SELECT 
        c.stay_id,
        c.subject_id,
        AVG(ce.valuenum) AS avg_sbp
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid IN (220179, 225309)  -- SBP items
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY c.stay_id, c.subject_id
),
categorized AS (
    SELECT 
        subject_id,
        CASE 
            WHEN avg_sbp < 140 THEN '<140'
            WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
            WHEN avg_sbp >= 160 THEN '>=160'
        END AS sbp_category
    FROM sbp_events
)
SELECT 
    sbp_category,
    COUNT(DISTINCT subject_id) AS patient_count
FROM categorized
GROUP BY sbp_category
ORDER BY sbp_category;