WITH diabetes_adms AS (
    -- Identify hospital admissions (hadm_id) with a diagnosis of Diabetes Mellitus
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for diabetes start with '250'
        (icd_version = 9 AND icd_code LIKE '250%')
        OR
        -- ICD-10 codes for diabetes start with 'E08', 'E09', 'E10', 'E11', 'E13'
        (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
),
heart_failure_adms AS (
    -- Identify hospital admissions (hadm_id) with a diagnosis of Heart Failure
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for heart failure start with '428'
        (icd_version = 9 AND icd_code LIKE '428%')
        OR
        -- ICD-10 codes for heart failure start with 'I50'
        (icd_version = 10 AND icd_code LIKE 'I50%')
),
target_cohort AS (
    -- Define the target patient cohort: Male, age 53-63, with both diabetes and heart failure diagnoses
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.anchor_age AS age_at_admission,
        pat.gender
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
    INNER JOIN
        diabetes_adms da ON adm.hadm_id = da.hadm_id
    INNER JOIN
        heart_failure_adms hfa ON adm.hadm_id = hfa.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 53 AND 63
        AND adm.dischtime IS NOT NULL -- Ensure discharge time exists for calculating the final 12 hours window
),
glp1_prescriptions AS (
    -- Find the earliest start time for any injectable GLP-1 RA prescription for each relevant admission
    SELECT
        t.hadm_id,
        MIN(p.starttime) AS first_glp1_starttime
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN
        target_cohort t ON p.subject_id = t.subject_id AND p.hadm_id = t.hadm_id
    WHERE
        -- Common injectable GLP-1 RA drug names (case-insensitive)
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%lixisenatide%'
    GROUP BY
        t.hadm_id
),
admission_flags AS (
    -- Join cohort with GLP-1 RA prescription data and set flags for initiation within windows
    SELECT
        tc.subject_id,
        tc.hadm_id,
        tc.admittime,
        tc.dischtime,
        gp.first_glp1_starttime,
        -- Flag: GLP-1 RA initiated within the first 24 hours of admission
        CASE
            WHEN gp.first_glp1_starttime IS NOT NULL
            AND gp.first_glp1_starttime >= tc.admittime
            AND gp.first_glp1_starttime <= TIMESTAMP_ADD(tc.admittime, INTERVAL 24 HOUR)
            THEN 1
            ELSE 0
        END AS initiated_first_24h,
        -- Flag: GLP-1 RA initiated within the final 12 hours before discharge
        CASE
            WHEN gp.first_glp1_starttime IS NOT NULL
            AND gp.first_glp1_starttime >= TIMESTAMP_SUB(tc.dischtime, INTERVAL 12 HOUR)
            AND gp.first_glp1_starttime <= tc.dischtime
            THEN 1
            ELSE 0
        END AS initiated_final_12h
    FROM
        target_cohort tc
    LEFT JOIN
        glp1_prescriptions gp ON tc.hadm_id = gp.hadm_id
)
-- Final aggregation to calculate counts and percentages
SELECT
    COUNT(DISTINCT hadm_id) AS total_target_admissions,
    SUM(initiated_first_24h) AS admissions_with_glp1_first_24h,
    SAFE_DIVIDE(SUM(initiated_first_24h), COUNT(DISTINCT hadm_id)) * 100 AS percentage_first_24h,
    SUM(initiated_final_12h) AS admissions_with_glp1_final_12h,
    SAFE_DIVIDE(SUM(initiated_final_12h), COUNT(DISTINCT hadm_id)) * 100 AS percentage_final_12h
FROM
    admission_flags;