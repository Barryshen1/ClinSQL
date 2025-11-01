WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        ie.stay_id,
        ie.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
),
rr_events AS (
    SELECT 
        c.stay_id,
        c.intime,
        ce.charttime,
        ce.valuenum AS respiratory_rate
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid IN (220210, 224422)  -- Respiratory rate itemids
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
)
SELECT 
    MIN(respiratory_rate) AS min_respiratory_rate
FROM rr_events;