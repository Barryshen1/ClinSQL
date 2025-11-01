WITH cohort_patients AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
        -- Ensure patient has diagnosis of Diabetes (ICD-10 codes E10-E14)
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_d
            WHERE
                diag_d.subject_id = ad.subject_id
                AND diag_d.hadm_id = ad.hadm_id
                AND diag_d.icd_version = 10
                AND (diag_d.icd_code LIKE 'E10%' OR diag_d.icd_code LIKE 'E11%' OR diag_d.icd_code LIKE 'E12%' OR diag_d.icd_code LIKE 'E13%' OR diag_d.icd_code LIKE 'E14%')
        )
        -- Ensure patient has diagnosis of Acute Heart Failure (ICD-10 codes I50.x)
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_hf
            WHERE
                diag_hf.subject_id = ad.subject_id
                AND diag_hf.hadm_id = ad.hadm_id
                AND diag_hf.icd_version = 10
                AND diag_hf.icd_code LIKE 'I50%'
        )
),
-- Step 2: Identify the first prescription time for each relevant medication class per admission
med_initiation_times AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.admittime,
        cp.dischtime,
        MIN(po.starttime) AS min_starttime_drug, -- First recorded starttime for the drug within this admission
        CASE
            WHEN LOWER(po.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(po.drug) LIKE '%glipizide%' OR LOWER(po.drug) LIKE '%glyburide%' OR LOWER(po.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(po.drug) LIKE '%sitagliptin%' OR LOWER(po.drug) LIKE '%saxagliptin%' OR LOWER(po.drug) LIKE '%linagliptin%' THEN 'DPP-4 inhibitors'
            WHEN LOWER(po.drug) LIKE '%canagliflozin%' OR LOWER(po.drug) LIKE '%dapagliflozin%' OR LOWER(po.drug) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitors'
            WHEN LOWER(po.drug) LIKE '%pioglitazone%' OR LOWER(po.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
            ELSE 'Other'
        END AS drug_class
    FROM
        cohort_patients AS cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS po
        ON cp.subject_id = po.subject_id
        AND cp.hadm_id = po.hadm_id
    WHERE
        -- Filter for the specific drug classes to optimize join
        (LOWER(po.drug) LIKE '%metformin%'
        OR LOWER(po.drug) LIKE '%glipi%' OR LOWER(po.drug) LIKE '%glybu%' OR LOWER(po.drug) LIKE '%glimepi%'
        OR LOWER(po.drug) LIKE '%sitagliptin%' OR LOWER(po.drug) LIKE '%saxagliptin%' OR LOWER(po.drug) LIKE '%linagliptin%'
        OR LOWER(po.drug) LIKE '%canagliflozin%' OR LOWER(po.drug) LIKE '%dapagliflozin%' OR LOWER(po.drug) LIKE '%empagliflozin%'
        OR LOWER(po.drug) LIKE '%pioglitazone%' OR LOWER(po.drug) LIKE '%rosiglitazone%')
    GROUP BY
        cp.subject_id,
        cp.hadm_id,
        cp.admittime,
        cp.dischtime,
        drug_class
    HAVING drug_class != 'Other' -- Exclude any drugs not categorized
),
-- Step 3: Categorize initiations into the specified time windows
categorized_initiations AS (
    SELECT
        mit.subject_id,
        mit.hadm_id,
        mit.drug_class,
        -- Flag if initiation occurred in the first 72 hours of admission
        CASE
            WHEN mit.min_starttime_drug >= mit.admittime
            AND mit.min_starttime_drug < TIMESTAMP_ADD(mit.admittime, INTERVAL 72 HOUR)
            THEN 1
            ELSE 0
        END AS initiated_in_first_72h,
        -- Flag if initiation occurred in the last 48 hours of admission
        -- The window's start is GREATEST(admittime, dischtime - 48 hours) to handle short stays
        CASE
            WHEN mit.min_starttime_drug >= GREATEST(mit.admittime, TIMESTAMP_SUB(mit.dischtime, INTERVAL 48 HOUR))
            AND mit.min_starttime_drug < mit.dischtime
            THEN 1
            ELSE 0
        END AS initiated_in_last_48h
    FROM
        med_initiation_times AS mit
),
-- Step 4: Calculate total cohort size for percentage calculation
total_cohort_admissions AS (
    SELECT
        COUNT(DISTINCT hadm_id) AS total_admissions_in_cohort
    FROM
        cohort_patients
)
-- Step 5: Summarize drug initiation rates by class for each time window
SELECT
    ci.drug_class,
    SUM(ci.initiated_in_first_72h) AS initiations_first_72h_count,
    ROUND((SUM(ci.initiated_in_first_72h) * 100.0 / tca.total_admissions_in_cohort), 2) AS perc_first_72h,
    SUM(ci.initiated_in_last_48h) AS initiations_last_48h_count,
    ROUND((SUM(ci.initiated_in_last_48h) * 100.0 / tca.total_admissions_in_cohort), 2) AS perc_last_48h
FROM
    categorized_initiations AS ci
CROSS JOIN
    total_cohort_admissions AS tca
GROUP BY
    ci.drug_class,
    tca.total_admissions_in_cohort
ORDER BY
    ci.drug_class;