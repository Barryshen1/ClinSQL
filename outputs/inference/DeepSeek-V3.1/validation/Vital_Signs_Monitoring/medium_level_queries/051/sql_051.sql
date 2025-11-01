WITH patient_max_hr AS (
    SELECT 
        ce.subject_id, 
        ce.stay_id,
        MAX(ce.valuenum) AS max_heart_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ce.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 55 AND 65
        AND ce.itemid = 220045  -- Heart rate
        AND ce.valuenum IS NOT NULL
    GROUP BY ce.subject_id, ce.stay_id
)
SELECT 
    APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] - APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS iqr
FROM patient_max_hr;