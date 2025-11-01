WITH vent_stays AS (
    SELECT DISTINCT ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` ie
    WHERE ie.itemid = 224385  -- Invasive Ventilation
),
bp_data AS (
    SELECT 
        ce.stay_id,
        ce.valuenum AS systolic_bp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
        ON ce.stay_id = icu.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON icu.subject_id = p.subject_id
    INNER JOIN vent_stays vs 
        ON ce.stay_id = vs.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 66 AND 76
        AND ce.itemid IN (220179, 220050)  -- Non-Invasive and Arterial systolic BP
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 6 HOUR)
)
SELECT 
    APPROX_QUANTILES(systolic_bp, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(systolic_bp, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(systolic_bp, 4)[OFFSET(3)] - APPROX_QUANTILES(systolic_bp, 4)[OFFSET(1)] AS iqr
FROM bp_data;