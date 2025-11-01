WITH cohort_admissions AS (
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
        AND pat.anchor_age BETWEEN 45 AND 55
),
hadm_with_diabetes AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '250%') -- ICD-9 Diabetes codes
        OR
        (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) -- ICD-10 Diabetes codes
),
hadm_with_heart_failure AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (icd_code = '39891' OR icd_code LIKE '402%' OR icd_code LIKE '404%' OR icd_code LIKE '428%')) -- ICD-9 Heart Failure codes
        OR
        (icd_version = 10 AND (icd_code = 'I0981' OR icd_code LIKE 'I110%' OR icd_code LIKE 'I130%' OR icd_code LIKE 'I132%' OR icd_code LIKE 'I50%')) -- ICD-10 Heart Failure codes
),
final_cohort AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime
    FROM
        cohort_admissions AS ca
    INNER JOIN
        hadm_with_diabetes AS dm
        ON ca.hadm_id = dm.hadm_id
    INNER JOIN
        hadm_with_heart_failure AS hf
        ON ca.hadm_id = hf.hadm_id
    WHERE ca.dischtime IS NOT NULL -- Ensure dischtime is not null for pre-discharge window calculation
),
total_cohort_count AS (
    SELECT COUNT(hadm_id) AS total_admissions
    FROM final_cohort
),
-- Step 3: Classify medications
med_classified AS (
    SELECT
        pr.subject_id,
        pr.hadm_id,
        pr.starttime,
        CASE
            WHEN lower(pr.drug) LIKE '%insulin%'
            OR lower(pr.drug) LIKE '%humalog%'
            OR lower(pr.drug) LIKE '%novolog%'
            OR lower(pr.drug) LIKE '%lantus%'
            OR lower(pr.drug) LIKE '%levemir%'
            OR lower(pr.drug) LIKE '%tresiba%'
            OR lower(pr.drug) LIKE '%apidra%'
            THEN 'Insulin'
            WHEN lower(pr.drug) LIKE '%metformin%'
            OR lower(pr.drug) LIKE '%glipizide%'
            OR lower(pr.drug) LIKE '%glyburide%'
            OR lower(pr.drug) LIKE '%glimepiride%'
            OR lower(pr.drug) LIKE '%pioglitazone%'
            OR lower(pr.drug) LIKE '%rosiglitazone%'
            OR lower(pr.drug) LIKE '%repaglinide%'
            OR lower(pr.drug) LIKE '%nateglinide%'
            OR lower(pr.drug) LIKE '%sitagliptin%'
            OR lower(pr.drug) LIKE '%saxagliptin%'
            OR lower(pr.drug) LIKE '%linagliptin%'
            OR lower(pr.drug) LIKE '%alogliptin%'
            OR lower(pr.drug) LIKE '%vildagliptin%'
            OR lower(pr.drug) LIKE '%empagliflozin%'
            OR lower(pr.drug) LIKE '%canagliflozin%'
            OR lower(pr.drug) LIKE '%dapagliflozin%'
            OR lower(pr.drug) LIKE '%ertugliflozin%'
            OR lower(pr.drug) LIKE '%dulaglutide%'
            OR lower(pr.drug) LIKE '%liraglutide%'
            OR lower(pr.drug) LIKE '%semaglutide%'
            OR lower(pr.drug) LIKE '%exenatide%'
            OR lower(pr.drug) LIKE '%lixisenatide%'
            OR lower(pr.drug) LIKE '%pramlintide%'
            THEN 'Oral Antidiabetic'
            ELSE NULL
        END AS med_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    WHERE
        pr.starttime IS NOT NULL
),
-- Step 4: Map medication events to time windows
med_events_with_windows AS (
    SELECT
        fc.hadm_id,
        mc.med_type,
        -- Check for initiation in the first 12 hours from admission
        CASE WHEN mc.starttime >= fc.admittime
                 AND mc.starttime <= DATETIME_ADD(fc.admittime, INTERVAL 12 HOUR)
            THEN 1 ELSE 0 END AS initiated_first_12h,
        -- Check for initiation in the final 72 hours before discharge
        CASE WHEN mc.starttime >= DATETIME_SUB(fc.dischtime, INTERVAL 72 HOUR)
                 AND mc.starttime <= fc.dischtime
            THEN 1 ELSE 0 END AS initiated_final_72h
    FROM
        final_cohort AS fc
    INNER JOIN
        med_classified AS mc
        ON fc.subject_id = mc.subject_id AND fc.hadm_id = mc.hadm_id
    WHERE mc.med_type IS NOT NULL -- Only include classified medications
),
-- Step 5: Determine if any initiation occurred per admission per med type in each window
initiation_flags AS (
    SELECT
        hadm_id,
        med_type,
        MAX(initiated_first_12h) AS initiated_first_12h, -- 1 if any initiation in this window for this hadm_id, 0 otherwise
        MAX(initiated_final_72h) AS initiated_final_72h -- 1 if any initiation in this window for this hadm_id, 0 otherwise
    FROM
        med_events_with_windows
    GROUP BY
        hadm_id, med_type
)
-- Step 6: Calculate rates and differences
SELECT
    med_type,
    COUNT(DISTINCT CASE WHEN initiated_first_12h = 1 THEN hadm_id END) AS num_initiated_first_12h,
    (COUNT(DISTINCT CASES WHEN initiated_first_12h = 1 THEN hadm_id END) * 100.0 / MAX(ttc.total_admissions)) AS rate_first_12h_percent,
    COUNT(DISTINCT CASE WHEN initiated_final_72h = 1 THEN hadm_id END) AS num_initiated_final_72h,
    (COUNT(DISTINCT CASES WHEN initiated_final_72h = 1 THEN hadm_id END) * 100.0 / MAX(ttc.total_admissions)) AS rate_final_72h_percent,
    (COUNT(DISTINCT CASES WHEN initiated_first_12h = 1 THEN hadm_id END) * 100.0 / MAX(ttc.total_admissions))
    -
    (COUNT(DISTINCT CASES WHEN initiated_final_72h = 1 THEN hadm_id END) * 100.0 / MAX(ttc.total_admissions)) AS pp_difference_first_minus_final
FROM
    initiation_flags
CROSS JOIN total_cohort_count AS ttc -- Use CROSS JOIN to make total_cohort_count available
GROUP BY
    med_type
ORDER BY
    med_type;