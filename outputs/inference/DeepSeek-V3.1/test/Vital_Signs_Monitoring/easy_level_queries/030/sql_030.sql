WITH first_hr AS (
    SELECT 
        ce.subject_id,
        ce.stay_id,
        MIN(ce.valuenum) AS first_hr_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.subject_id = ie.subject_id 
        AND ce.hadm_id = ie.hadm_id 
        AND ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ce.subject_id = p.subject_id
    WHERE ce.itemid = 220045  -- Heart Rate itemid
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 300  -- reasonable range for heart rate
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 1 HOUR)  -- first hour of ICU admission
    GROUP BY ce.subject_id, ce.stay_id
)
SELECT MIN(first_hr_value) AS min_first_heart_rate
FROM first_hr;