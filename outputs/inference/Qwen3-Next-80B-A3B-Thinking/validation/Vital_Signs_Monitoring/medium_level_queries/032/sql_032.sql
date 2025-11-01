WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        i.stay_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON p.subject_id = i.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND (i.first_careunit LIKE '%Step Down%' OR i.first_careunit LIKE '%IMC%')
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
            WHERE ce.stay_id = i.stay_id
                AND ce.itemid = 720
                AND ce.value = 'On'
        )
)
SELECT STDDEV(valuenum) AS sbp_stddev
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN eligible_patients ep 
    ON ce.stay_id = ep.stay_id
WHERE ce.itemid = 6701
    AND ce.charttime BETWEEN ep.intime AND ep.outtime
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5
    AND ce.valuenum IS NOT NULL;