WITH rrt_admissions AS (
    SELECT DISTINCT
        p_icd.subject_id,
        p_icd.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    WHERE
        -- ICD-9-CM codes for Hemodialysis (39.95) and Other Peritoneal Dialysis (58.49)
        (p_icd.icd_version = 9 AND p_icd.icd_code IN ('3995', '5849'))
        OR
        -- ICD-10-PCS codes for various Extracorporeal Assistance and Performance, particularly Hemodialysis and Peritoneal Dialysis.
        -- Many RRT procedures start with '5A1D' (Hemodialysis) or '5A1E' (Peritoneal Dialysis)
        (p_icd.icd_version = 10 AND (p_icd.icd_code LIKE '5A1D%' OR p_icd.icd_code LIKE '5A1E%'))
),
-- Step 2: Define the eligible patient cohort
-- - Female gender
-- - Aged 52-62 at hospital admission (using anchor_age as approximation)
-- - Had an ICU stay
-- - Received RRT during their associated hospital admission
cohort_patients AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los AS icu_los, -- ICU length of stay in days
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    INNER JOIN rrt_admissions rrt
        ON ie.hadm_id = rrt.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 52 AND 62
),
-- Step 3: Calculate the first-72-hour vital-sign instability score for each patient in the cohort
-- Score: Count of individual vital sign measurements outside normal range per ICU stay
vital_sign_scores AS (
    SELECT
        cp.stay_id,
        cp.icu_los,
        cp.hospital_expire_flag,
        COUNT(CASE
            -- Heart Rate (itemids: 220045, 227096). Normal range: 60-100 bpm
            WHEN ce.itemid IN (220045, 227096) AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
            -- Respiratory Rate (itemids: 220210, 227090). Normal range: 12-20 breaths/min
            WHEN ce.itemid IN (220210, 227090) AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1
            -- Systolic Blood Pressure (itemids: 220050, 220179, 227243). Normal range: 90-140 mmHg
            WHEN ce.itemid IN (220050, 220179, 227243) AND (ce.valuenum < 90 OR ce.valuenum > 140) THEN 1
            -- Diastolic Blood Pressure (itemids: 220051, 220180, 227244). Normal range: 60-90 mmHg
            WHEN ce.itemid IN (220051, 220180, 227244) AND (ce.valuenum < 60 OR ce.valuenum > 90) THEN 1
            -- Temperature Celsius (itemid: 223761). Normal range: 36.5-37.5 C
            WHEN ce.itemid = 223761 AND (ce.valuenum < 36.5 OR ce.valuenum > 37.5) THEN 1
            -- Temperature Fahrenheit (itemid: 223762). Normal range: 97.7-99.5 F
            WHEN ce.itemid = 223762 AND (ce.valuenum < 97.7 OR ce.valuenum > 99.5) THEN 1
            -- SpO2 (itemid: 220277). Normal range: 92-100%
            WHEN ce.itemid = 220277 AND (ce.valuenum < 92 OR ce.valuenum > 100) THEN 1
            ELSE NULL -- Only count unstable vital signs
        END) AS vital_instability_score
    FROM cohort_patients cp
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cp.stay_id = ce.stay_id
    WHERE
        ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.charttime BETWEEN cp.intime AND DATETIME_ADD(cp.intime, INTERVAL 72 HOUR) -- Within first 72 hours of ICU stay
        AND ce.itemid IN (
            220045, 227096, -- HR
            220210, 227090, -- RR
            220050, 220179, 227243, -- SBP
            220051, 220180, 227244, -- DBP
            223761, 223762, -- Temp
            220277 -- SpO2
        )
    GROUP BY
        cp.stay_id, cp.icu_los, cp.hospital_expire_flag
),
-- Step 4: Rank scores to determine percentiles and deciles
ranked_scores AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY vital_instability_score ASC) AS percentile_rank,
        NTILE(10) OVER (ORDER BY vital_instability_score DESC) AS decile_rank -- 1 for top 10% (highest scores), 10 for bottom 10% (lowest scores)
    FROM vital_sign_scores
    WHERE vital_instability_score IS NOT NULL
)
-- Final SELECT statement to present the results
SELECT
    -- Part 1: Percentile for a vital-sign instability score of 65
    IFNULL(
        (SELECT MAX(percentile_rank) * 100 -- Get the highest percentile rank for scores <= 65
         FROM ranked_scores
         WHERE vital_instability_score <= 65),
        NULL -- Return NULL if no scores are <= 65 in the cohort
    ) AS percentile_for_score_65,

    -- Part 2: Mean ICU length of stay and mortality for the top decile
    AVG(CASE WHEN r.decile_rank = 1 THEN r.icu_los END) AS mean_icu_los_top_decile,
    AVG(CASE WHEN r.decile_rank = 1 THEN r.hospital_expire_flag END) AS mortality_rate_top_decile
FROM ranked_scores AS r
-- Note: the AVG(CASE WHEN ... END) handles the filtering for `decile_rank = 1` implicitly
-- if there are no patients in the top decile, these averages will be NULL.
;