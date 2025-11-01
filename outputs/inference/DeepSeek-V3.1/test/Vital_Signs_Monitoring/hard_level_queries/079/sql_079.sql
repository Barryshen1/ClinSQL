WITH hfnc_patients AS (
    -- Identify patients receiving HFNC in first 48h
    SELECT DISTINCT
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ie.stay_id = icu.stay_id
    WHERE ie.itemid = 226168  -- HFNC oxygen therapy
        AND ie.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
),
instability_markers AS (
    -- Calculate instability markers in first 48h
    SELECT 
        hp.stay_id,
        -- Vasopressor use
        MAX(CASE WHEN ie.itemid IN (221906, 221289,  -- norepinephrine
                                    221662, 221653) -- epinephrine
                 THEN 1 ELSE 0 END) AS vasopressor_used,
        -- Mechanical ventilation
        MAX(CASE WHEN ce.itemid = 224685 -- ventilator mode
                 AND ce.value IS NOT NULL 
                 THEN 1 ELSE 0 END) AS mechanical_vent,
        -- High lactate (>2 mmol/L)
        MAX(CASE WHEN le.itemid = 50813 -- lactate
                 AND le.valuenum > 2 
                 THEN 1 ELSE 0 END) AS high_lactate,
        -- Low MAP (<65 mmHg)
        MAX(CASE WHEN ce.itemid = 220052 -- mean arterial pressure
                 AND ce.valuenum < 65 
                 THEN 1 ELSE 0 END) AS low_map
    FROM hfnc_patients hp
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON hp.stay_id = ie.stay_id
        AND ie.starttime BETWEEN (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id)
                            AND DATETIME_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id), INTERVAL 48 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON hp.stay_id = ce.stay_id
        AND ce.charttime BETWEEN (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id)
                            AND DATETIME_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id), INTERVAL 48 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON hp.hadm_id = le.hadm_id
        AND le.charttime BETWEEN (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id)
                            AND DATETIME_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = hp.stay_id), INTERVAL 48 HOUR)
    GROUP BY hp.stay_id
),
cohort AS (
    SELECT 
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        pat.anchor_age,
        adm.hospital_expire_flag,
        icu.los AS icu_los,
        -- Composite instability score (simplified)
        (COALESCE(im.vasopressor_used, 0) + 
         COALESCE(im.mechanical_vent, 0) + 
         COALESCE(im.high_lactate, 0) + 
         COALESCE(im.low_map, 0)) AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN hfnc_patients hp
        ON icu.stay_id = hp.stay_id
    LEFT JOIN instability_markers im
        ON icu.stay_id = im.stay_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 81 AND 91
),
percentile_info AS (
    SELECT
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank,
        subject_id,
        hadm_id,
        stay_id,
        instability_score,
        icu_los,
        hospital_expire_flag
    FROM cohort
),
percentile_85 AS (
    SELECT
        MAX(percentile_rank) AS percentile_for_85
    FROM percentile_info
    WHERE instability_score <= 85
),
top_decile AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        instability_score,
        icu_los,
        hospital_expire_flag
    FROM percentile_info
    WHERE percentile_rank >= 0.9
)
SELECT
    (SELECT percentile_for_85 FROM percentile_85) AS percentile_for_score_85,
    AVG(icu_los) AS avg_icu_los_top_decile,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent_top_decile
FROM top_decile;