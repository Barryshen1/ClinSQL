WITH heart_rate AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        ie.stay_id,
        MIN(ce.valuenum) AS min_heart_rate
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 44 AND 54
        AND ce.itemid = 220045  -- Heart rate
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ie.intime
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    GROUP BY p.subject_id, p.gender, p.anchor_age, ie.stay_id
)
SELECT 
    subject_id,
    stay_id,
    anchor_age,
    min_heart_rate
FROM heart_rate
ORDER BY subject_id, stay_id;