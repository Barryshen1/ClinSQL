WITH abg_pH AS (
    SELECT 
        ie.stay_id,
        ce.valuenum AS pH_value
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.subject_id = ce.subject_id
            AND ie.hadm_id = ce.hadm_id
            AND ie.stay_id = ce.stay_id
    WHERE p.gender = 'F'
        AND ce.itemid = 780  -- Arterial Blood Gas pH
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 6 HOUR)
)
SELECT 
    PERCENTILE_CONT(pH_value, 0.5) OVER() AS median_pH
FROM abg_pH
LIMIT 1;