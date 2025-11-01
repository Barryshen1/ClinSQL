WITH vent_patients AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        t.stay_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` t
        ON a.hadm_id = t.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON t.stay_id = pe.stay_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND pe.itemid = 224385  -- Invasive Ventilation
        AND t.first_careunit IN ('Step Down', 'IMC')  -- Filter for step-down/IMC stays
)
SELECT 
    STDDEV(ce.valuenum) AS sbp_stddev
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN vent_patients v
    ON ce.stay_id = v.stay_id
WHERE ce.itemid = 220179  -- Invasive SBP
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5  -- 00:00 to 05:59 (nighttime)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 
    AND ce.valuenum < 300;  -- Reasonable SBP range;