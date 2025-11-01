WITH first_spo2 AS (
    SELECT 
        ce.stay_id,
        ce.valuenum AS spo2_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        AND ce.itemid = 220277  -- SpO2
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- Exclude negative values
        AND ce.charttime >= ie.intime  -- Ensure measurement during ICU stay
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 1 HOUR)  -- First hour of admission
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
    APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS iqr
FROM first_spo2;