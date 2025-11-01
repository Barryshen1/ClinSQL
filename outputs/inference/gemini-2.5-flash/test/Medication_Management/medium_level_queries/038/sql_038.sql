WITH cohort_admissions AS (
    -- Step 1: Identify the cohort - male inpatients 57-67 with diabetes and acute HF
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 57 AND 67
        -- Check for Diabetes diagnosis (ICD-9: 250.xx, ICD-10: E10.xx, E11.xx, E13.xx)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE di.hadm_id = adm.hadm_id
            AND (
                (di.icd_version = 9 AND di.icd_code LIKE '250%') OR
                (di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%'))
            )
        )
        -- Check for Acute Heart Failure diagnosis (ICD-9: 428.xx, ICD-10: I50.xx)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE di.hadm_id = adm.hadm_id
            AND (
                (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
                (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
            )
        )
),
glp1_prescriptions AS (
    -- Step 2: Identify GLP-1 agonist prescriptions
    SELECT
        p.subject_id,
        p.hadm_id,
        p.starttime
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE
        LOWER(p.drug) IN (
            'exenatide', 'liraglutide', 'semaglutide', 'dulaglutide', 'lixisenatide', 'tirzepatide'
        )
),
admissions_with_glp1_info AS (
    -- Step 3: Determine GLP-1 usage and first prescription time for each cohort admission
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        MIN(gp.starttime) AS first_glp1_rx_time, -- Earliest GLP-1 prescription for this admission
        -- Flag if any GLP-1 prescription occurred in the first 72 hours
        MAX(CASE
            WHEN gp.starttime IS NOT NULL
            AND gp.starttime >= ca.admittime
            AND gp.starttime < DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
            THEN 1 ELSE 0
        END) AS any_glp1_first_72h,
        -- Flag if any GLP-1 prescription occurred in the final 24 hours
        MAX(CASE
            WHEN gp.starttime IS NOT NULL
            AND gp.starttime >= DATETIME_SUB(ca.dischtime, INTERVAL 24 HOUR)
            AND gp.starttime < ca.dischtime
            THEN 1 ELSE 0
        END) AS any_glp1_final_24h
    FROM
        cohort_admissions AS ca
    LEFT JOIN
        glp1_prescriptions AS gp
        ON ca.hadm_id = gp.hadm_id
    GROUP BY
        ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime
),
final_cohort_data AS (
    -- Step 4: Calculate initiation and prevalence flags for each admission
    SELECT
        ad.hadm_id,
        ad.any_glp1_first_72h,
        ad.any_glp1_final_24h,
        -- Flag if GLP-1 was initiated (first prescription) in the first 72 hours
        CASE
            WHEN ad.first_glp1_rx_time IS NOT NULL
            AND ad.first_glp1_rx_time >= ad.admittime
            AND ad.first_glp1_rx_time < DATETIME_ADD(ad.admittime, INTERVAL 72 HOUR)
            THEN 1
            ELSE 0
        END AS initiated_first_72h,
        -- Flag if GLP-1 was initiated (first prescription) in the final 24 hours
        CASE
            WHEN ad.first_glp1_rx_time IS NOT NULL
            AND ad.first_glp1_rx_time >= DATETIME_SUB(ad.dischtime, INTERVAL 24 HOUR)
            AND ad.first_glp1_rx_time < ad.dischtime
            THEN 1
            ELSE 0
        END AS initiated_final_24h_window
    FROM
        admissions_with_glp1_info AS ad
)
-- Step 5: Aggregate and calculate final metrics
SELECT
    COUNT(DISTINCT fcd.hadm_id) AS total_cohort_admissions,

    -- Prevalence in first 72 hours
    COUNT(CASE WHEN fcd.any_glp1_first_72h = 1 THEN fcd.hadm_id END) AS num_prevalent_first_72h,
    SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100 AS pct_prevalent_first_72h,

    -- Prevalence in final 24 hours
    COUNT(CASE WHEN fcd.any_glp1_final_24h = 1 THEN fcd.hadm_id END) AS num_prevalent_final_24h,
    SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_final_24h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100 AS pct_prevalent_final_24h,

    -- Initiation in first 72 hours
    COUNT(CASE WHEN fcd.initiated_first_72h = 1 THEN fcd.hadm_id END) AS num_initiated_first_72h,
    SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100 AS pct_initiated_first_72h,

    -- Initiation in final 24 hours
    COUNT(CASE WHEN fcd.initiated_final_24h_window = 1 THEN fcd.hadm_id END) AS num_initiated_final_24h,
    SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_final_24h_window = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100 AS pct_initiated_final_24h,

    -- --- Derive absolute and relative changes from the calculated percentages ---
    -- Absolute Change for Prevalence
    (SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_final_24h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) -
    (SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) AS abs_change_prevalence_pct,

    -- Relative Change for Prevalence
    SAFE_DIVIDE(
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_final_24h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) -
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100),
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.any_glp1_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100)
    ) * 100 AS rel_change_prevalence_pct,

    -- Absolute Change for Initiation
    (SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_final_24h_window = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) -
    (SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) AS abs_change_initiation_pct,

    -- Relative Change for Initiation
    SAFE_DIVIDE(
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_final_24h_window = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100) -
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100),
        (SAFE_DIVIDE(COUNT(CASE WHEN fcd.initiated_first_72h = 1 THEN fcd.hadm_id END), COUNT(DISTINCT fcd.hadm_id)) * 100)
    ) * 100 AS rel_change_initiation_pct
FROM
    final_cohort_data AS fcd;