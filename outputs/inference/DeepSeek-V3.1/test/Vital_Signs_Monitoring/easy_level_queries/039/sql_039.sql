WITH first_rr AS (
    SELECT 
        ce.valuenum AS resp_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE ce.itemid = 220210 -- Respiratory rate
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 51 AND 61
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 1 HOUR)
        AND ce.valuenum IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
    APPROX_QUANTILES(resp_rate, 100)[OFFSET(25)] AS percentile_25
FROM first_rr;