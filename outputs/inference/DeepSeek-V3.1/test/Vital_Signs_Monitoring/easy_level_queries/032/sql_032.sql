WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        ie.stay_id,
        ie.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
), rr_events AS (
    SELECT 
        c.subject_id,
        c.anchor_age,
        c.stay_id,
        ce.charttime,
        ce.valuenum AS respiratory_rate
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220210  -- Respiratory rate (measured in breaths per minute)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- exclude invalid values
        AND ce.charttime >= c.intime
        AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
)
SELECT 
    subject_id,
    anchor_age,
    stay_id,
    MAX(respiratory_rate) AS max_respiratory_rate
FROM rr_events
GROUP BY subject_id, anchor_age, stay_id
ORDER BY anchor_age, subject_id;