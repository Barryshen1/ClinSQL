WITH CohortPatients AS (
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        pa.gender,
        pa.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 38 AND 48
    AND EXISTS ( -- Has Type 2 Diabetes diagnosis
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_t2d
        WHERE
            d_t2d.subject_id = ad.subject_id
            AND d_t2d.hadm_id = ad.hadm_id
            AND (
                -- ICD-9 T2D codes (250.x for T2D without specific type, or with complications specific to T2D)
                -- Exclude Type 1 diabetes, generally covers T2D
                (d_t2d.icd_version = 9 AND d_t2d.icd_code LIKE '250.%' AND d_t2d.icd_code NOT IN ('250.10', '250.11', '250.12', '250.13'))
                OR (d_t2d.icd_version = 10 AND d_t2d.icd_code LIKE 'E11%') -- ICD-10 T2D
            )
    )
    AND EXISTS ( -- Has Heart Failure diagnosis
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_hf
        WHERE
            d_hf.subject_id = ad.subject_id
            AND d_hf.hadm_id = ad.hadm_id
            AND (
                (d_hf.icd_version = 9 AND d_hf.icd_code LIKE '428%') -- ICD-9 HF
                OR (d_hf.icd_version = 10 AND d_hf.icd_code LIKE 'I50%') -- ICD-10 HF
            )
    )
),
-- Step 2: Identify medication administrations for the cohort, categorizing them
MedicationAdministrations AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.admittime,
        cp.dischtime,
        emar.charttime,
        LOWER(emar.medication) AS medication_lower,
        CASE WHEN LOWER(emar.medication) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
        CASE
            WHEN LOWER(emar.medication) LIKE '%metformin%' OR
                 LOWER(emar.medication) LIKE '%glipizide%' OR
                 LOWER(emar.medication) LIKE '%glyburi%' OR -- Handles glyburide
                 LOWER(emar.medication) LIKE '%glimepiride%' OR
                 LOWER(emar.medication) LIKE '%sitagliptin%' OR
                 LOWER(emar.medication) LIKE '%saxagliptin%' OR
                 LOWER(emar.medication) LIKE '%linagliptin%' OR
                 LOWER(emar.medication) LIKE '%alogliptin%' OR
                 LOWER(emar.medication) LIKE '%canagliflozin%' OR
                 LOWER(emar.medication) LIKE '%dapagliflozin%' OR
                 LOWER(emar.medication) LIKE '%empagliflozin%' OR
                 LOWER(emar.medication) LIKE '%pioglitazone%' OR
                 LOWER(emar.medication) LIKE '%rosiglitazone%' OR
                 LOWER(emar.medication) LIKE '%acarbose%' OR
                 LOWER(emar.medication) LIKE '%miglitol%' OR
                 LOWER(emar.medication) LIKE '%repaglinide%' OR -- Meglitinides
                 LOWER(emar.medication) LIKE '%nateglinide%' -- Meglitinides
            THEN 1 ELSE 0
        END AS is_oral_agent
    FROM
        CohortPatients AS cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.emar` AS emar
        ON cp.subject_id = emar.subject_id AND cp.hadm_id = emar.hadm_id
    WHERE
        emar.charttime IS NOT NULL
        AND emar.medication IS NOT NULL
),
-- Step 3: Determine initiation status within the specified time windows for each patient admission
PatientInitiationStatus AS (
    SELECT
        subject_id,
        hadm_id,
        MAX(CASE
            -- First 72 hours window, capped by discharge time
            WHEN charttime >= admittime
            AND charttime <= DATETIME_ADD(admittime, INTERVAL 72 HOUR)
            AND charttime <= dischtime -- Ensure not past discharge
            AND is_insulin = 1
            THEN 1 ELSE 0
        END) AS initiated_insulin_first_72h,
        MAX(CASE
            WHEN charttime >= admittime
            AND charttime <= DATETIME_ADD(admittime, INTERVAL 72 HOUR)
            AND charttime <= dischtime
            AND is_oral_agent = 1
            THEN 1 ELSE 0
        END) AS initiated_oral_first_72h,
        MAX(CASE
            -- Last 72 hours window, starting no earlier than admittime
            WHEN charttime >= DATETIME_SUB(dischtime, INTERVAL 72 HOUR)
            AND charttime >= admittime -- Ensure not before admission
            AND charttime <= dischtime
            AND is_insulin = 1
            THEN 1 ELSE 0
        END) AS initiated_insulin_last_72h,
        MAX(CASE
            WHEN charttime >= DATETIME_SUB(dischtime, INTERVAL 72 HOUR)
            AND charttime >= admittime
            AND charttime <= dischtime
            AND is_oral_agent = 1
            THEN 1 ELSE 0
        END) AS initiated_oral_last_72h
    FROM
        MedicationAdministrations
    GROUP BY
        subject_id,
        hadm_id
)
-- Step 4: Calculate final percentages
SELECT
    COUNT(*) AS total_cohort_admissions, -- Fixed: Using COUNT(*) for total admissions
    (SUM(pis.initiated_insulin_first_72h) * 100.0 / COUNT(*)) AS percent_initiated_insulin_first_72h,
    (SUM(pis.initiated_oral_first_72h) * 100.0 / COUNT(*)) AS percent_initiated_oral_first_72h,
    (SUM(pis.initiated_insulin_last_72h) * 100.0 / COUNT(*)) AS percent_initiated_insulin_last_72h,
    (SUM(pis.initiated_oral_last_72h) * 100.0 / COUNT(*)) AS percent_initiated_oral_last_72h
FROM
    PatientInitiationStatus AS pis;