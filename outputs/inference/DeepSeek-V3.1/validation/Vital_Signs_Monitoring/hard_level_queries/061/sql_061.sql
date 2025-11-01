WITH cohort AS (
    SELECT 
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.los AS icu_los,
        a.hospital_expire_flag,
        -- Calculate a composite vital instability score from first 24h vitals
        -- This is a simplified example using common vital signs
        AVG(
            CASE 
                WHEN ce.itemid IN (220045, 220050) THEN -- Heart rate
                    CASE WHEN ce.valuenum BETWEEN 60 AND 100 THEN 0 
                         WHEN ce.valuenum BETWEEN 40 AND 59 OR ce.valuenum BETWEEN 101 AND 120 THEN 25
                         WHEN ce.valuenum < 40 OR ce.valuenum > 120 THEN 50
                         ELSE 0 END
                WHEN ce.itemid IN (220179, 220180) THEN -- Systolic BP
                    CASE WHEN ce.valuenum BETWEEN 90 AND 140 THEN 0
                         WHEN ce.valuenum BETWEEN 70 AND 89 OR ce.valuenum BETWEEN 141 AND 180 THEN 25
                         WHEN ce.valuenum < 70 OR ce.valuenum > 180 THEN 50
                         ELSE 0 END
                WHEN ce.itemid IN (220210, 220277) THEN -- Respiratory rate
                    CASE WHEN ce.valuenum BETWEEN 12 AND 20 THEN 0
                         WHEN ce.valuenum BETWEEN 8 AND 11 OR ce.valuenum BETWEEN 21 AND 25 THEN 25
                         WHEN ce.valuenum < 8 OR ce.valuenum > 25 THEN 50
                         ELSE 0 END
                WHEN ce.itemid IN (223761, 223762) THEN -- Temperature
                    CASE WHEN ce.valuenum BETWEEN 36.0 AND 38.0 THEN 0
                         WHEN ce.valuenum BETWEEN 35.0 AND 35.9 OR ce.valuenum BETWEEN 38.1 AND 39.0 THEN 25
                         WHEN ce.valuenum < 35.0 OR ce.valuenum > 39.0 THEN 50
                         ELSE 0 END
                ELSE 0
            END
        ) AS composite_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (220045, 220050, 220179, 220180, 220210, 220277, 223761, 223762)
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 49 AND 59
    GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.los, a.hospital_expire_flag
    HAVING composite_score IS NOT NULL
),

percentile_calc AS (
    SELECT
        composite_score,
        PERCENT_RANK() OVER (ORDER BY composite_score) AS percentile_rank,
        PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90_score
    FROM cohort
),

percentile_of_70 AS (
    SELECT 
        MIN(percentile_rank) AS percentile_value
    FROM percentile_calc
    WHERE composite_score >= 70
),

top_decile AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.icu_los,
        c.hospital_expire_flag
    FROM cohort c
    INNER JOIN percentile_calc pc
        ON c.composite_score = pc.composite_score
    WHERE c.composite_score >= pc.p90_score
)

SELECT
    (SELECT percentile_value FROM percentile_of_70) AS percentile_of_70,
    AVG(icu_los) AS mean_icu_los_top_decile,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent_top_decile
FROM top_decile;