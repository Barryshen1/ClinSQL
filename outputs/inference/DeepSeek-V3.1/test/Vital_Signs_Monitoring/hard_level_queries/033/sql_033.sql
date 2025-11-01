WITH sofa_scores AS (
    -- Placeholder for SOFA calculation per stay in first 48 hours
    -- In practice, you would compute each component and sum them.
    SELECT 
        ie.stay_id,
        -- Example: respiratory component (simplified)
        MAX(CASE 
            WHEN ce.itemid IN (224690, 224689) AND ce.valuenum > 0 THEN 4  -- Mechanical ventilation
            ELSE 0 
        END) AS respiratory_score,
        -- Add other components here: cardiovascular, hepatic, coagulation, renal, neurological
        -- Then sum them as sofa_score
        -- For now, we use a placeholder value: assume we have a computed sofa_score
        -- Since we don't have the actual logic, we'll use a random number between 0 and 24 for demonstration.
        -- REPLACE WITH ACTUAL SOFA CALCULATION.
        ROUND(RAND() * 24) AS sofa_score   -- Placeholder: random score between 0 and 24
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
    GROUP BY ie.stay_id
),

cohort AS (
    SELECT 
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        p.anchor_age,
        a.hospital_expire_flag,
        ie.los AS icu_los,
        ss.sofa_score AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    INNER JOIN sofa_scores ss
        ON ie.stay_id = ss.stay_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 51 AND 61
),

percentiles AS (
    SELECT
        DISTINCT
        PERCENTILE_CONT(instability_score, 0.1) OVER() AS p10,
        PERCENTILE_CONT(instability_score, 0.2) OVER() AS p20,
        PERCENTILE_CONT(instability_score, 0.3) OVER() AS p30,
        PERCENTILE_CONT(instability_score, 0.4) OVER() AS p40,
        PERCENTILE_CONT(instability_score, 0.5) OVER() AS p50,
        PERCENTILE_CONT(instability_score, 0.6) OVER() AS p60,
        PERCENTILE_CONT(instability_score, 0.7) OVER() AS p70,
        PERCENTILE_CONT(instability_score, 0.8) OVER() AS p80,
        PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
    FROM cohort
),

target_percentile AS (
    SELECT
        CASE
            WHEN 80 <= p10 THEN 10
            WHEN 80 <= p20 THEN 20
            WHEN 80 <= p30 THEN 30
            WHEN 80 <= p40 THEN 40
            WHEN 80 <= p50 THEN 50
            WHEN 80 <= p60 THEN 60
            WHEN 80 <= p70 THEN 70
            WHEN 80 <= p80 THEN 80
            WHEN 80 <= p90 THEN 90
            ELSE 100
        END AS percentile
    FROM percentiles
),

top_decile AS (
    SELECT
        AVG(icu_los) AS avg_icu_los,
        AVG(hospital_expire_flag) AS mortality_rate
    FROM cohort
    CROSS JOIN percentiles
    WHERE instability_score >= p90
)

SELECT
    (SELECT percentile FROM target_percentile) AS percentile_for_80,
    (SELECT avg_icu_los FROM top_decile) AS avg_icu_los_top_decile,
    (SELECT mortality_rate FROM top_decile) AS mortality_rate_top_decile
;