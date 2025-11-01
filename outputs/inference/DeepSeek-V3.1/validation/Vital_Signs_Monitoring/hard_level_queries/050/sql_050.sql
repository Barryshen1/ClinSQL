WITH cohort AS (
    -- Female ICU patients aged 52-62 who received RRT
    SELECT DISTINCT ie.subject_id, ie.hadm_id, ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
        AND (
            -- RRT in procedureevents
            EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
                WHERE ie.stay_id = pe.stay_id
                    AND pe.itemid IN (225802, 225803) -- CRRT and IHD
            )
            OR
            -- RRT in procedures_icd
            EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
                WHERE ie.hadm_id = picd.hadm_id
                    AND (picd.icd_code = '39.95' AND picd.icd_version = 9
                         OR picd.icd_code LIKE '5A1D%' AND picd.icd_version = 10)
            )
        )
),

vitals AS (
    -- Extract vital signs for cohort patients during first 72 hours of ICU stay
    SELECT ce.stay_id,
        ce.itemid,
        CASE
            WHEN ce.itemid = 220045 THEN 'HR'
            WHEN ce.itemid = 220179 THEN 'SBP'
            WHEN ce.itemid = 220180 THEN 'DBP'
            WHEN ce.itemid = 220181 THEN 'MAP'
            WHEN ce.itemid = 220210 THEN 'RR'
            WHEN ce.itemid = 220277 THEN 'SpO2'
        END AS vital_type,
        ce.valuenum AS value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN cohort c
        ON ce.stay_id = c.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    WHERE ce.itemid IN (220045, 220179, 220180, 220181, 220210, 220277)
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
),

vitals_stats AS (
    -- Calculate mean and stddev for each vital sign per stay
    SELECT stay_id,
        vital_type,
        AVG(value) AS mean_value,
        STDDEV(value) AS std_value
    FROM vitals
    GROUP BY stay_id, vital_type
),

vitals_cv AS (
    -- Compute coefficient of variation for each vital sign
    SELECT stay_id,
        vital_type,
        std_value / mean_value AS cv
    FROM vitals_stats
    WHERE mean_value > 0  -- avoid division by zero
),

instability_scores AS (
    -- Average CV across vital signs to get instability score per patient
    SELECT stay_id,
        AVG(cv) * 100 AS instability_score  -- scale to percentage-like
    FROM vitals_cv
    GROUP BY stay_id
),

cohort_with_scores AS (
    -- Combine cohort with instability scores
    SELECT c.subject_id, c.hadm_id, c.stay_id,
        COALESCE(i.instability_score, 0) AS instability_score,  -- if no vitals, score=0
        ie.los,
        a.hospital_expire_flag
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON c.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
    LEFT JOIN instability_scores i
        ON c.stay_id = i.stay_id
),

percentile_calc AS (
    -- Calculate the percentile of score 65 and the 90th percentile threshold
    SELECT 
        APPROX_QUANTILES(instability_score, 100) AS percentiles,
        (SELECT COUNT(*) 
         FROM cohort_with_scores 
         WHERE instability_score <= 65) * 100.0 / 
        (SELECT COUNT(*) 
         FROM cohort_with_scores) AS percentile_of_65
    FROM cohort_with_scores
),

top_decile_threshold AS (
    -- Calculate the 90th percentile threshold
    SELECT 
        APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS threshold_90th
    FROM cohort_with_scores
)

-- Main query using pre-calculated values
SELECT 
    (SELECT percentile_of_65 FROM percentile_calc) AS percentile_of_65,
    AVG(CASE WHEN cws.instability_score >= (SELECT threshold_90th FROM top_decile_threshold) 
             THEN cws.los END) AS mean_los_top_decile,
    AVG(CASE WHEN cws.instability_score >= (SELECT threshold_90th FROM top_decile_threshold) 
             THEN cws.hospital_expire_flag END) AS mortality_top_decile
FROM cohort_with_scores cws;