WITH cohort_candidate AS (
    -- Step 1: Define the initial cohort based on gender, age, and admission duration
    -- Join admissions, patients, and diagnoses to prepare for filtering
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        di.icd_code,
        di.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ca.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 66 AND 76
        AND TIMESTAMP_DIFF(ca.dischtime, ca.admittime, HOUR) >= 72
),
cohort AS (
    -- Step 2: Filter cohort_candidate to ensure both Diabetes and Heart Failure diagnoses are present
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime
    FROM
        cohort_candidate
    GROUP BY
        subject_id,
        hadm_id,
        admittime,
        dischtime
    HAVING
        -- Diabetes diagnosis (ICD-9: 250%, ICD-10: E08-E13)
        COUNT(DISTINCT CASE
            WHEN (icd_version = 9 AND icd_code LIKE '250%') OR
                 (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'))
            THEN 1 END) >= 1
        -- Heart Failure diagnosis (ICD-9: 428%, ICD-10: I50%)
        AND COUNT(DISTINCT CASE
            WHEN (icd_version = 9 AND icd_code LIKE '428%') OR
                 (icd_version = 10 AND icd_code LIKE 'I50%')
            THEN 1 END) >= 1
),
meds_with_classes AS (
    -- Step 3: Identify antidiabetic medications for the cohort and categorize them into classes
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        p.drug,
        p.starttime,
        p.stoptime,
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanides'
            WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
            WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
            WHEN LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 Receptor Agonists'
            WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
            WHEN LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' THEN 'Meglitinides'
            WHEN LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%' THEN 'Alpha-glucosidase Inhibitors'
            WHEN LOWER(p.drug) LIKE '%pramlintide%' THEN 'Amylin Analogs'
            ELSE NULL -- Only include specific antidiabetic classes
        END AS antidiabetic_class
    FROM
        cohort c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
    WHERE
        -- Pre-filter for common antidiabetic drug keywords to optimize the CASE statement
        LOWER(p.drug) LIKE '%insulin%' OR
        LOWER(p.drug) LIKE '%metformin%' OR
        LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR
        LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR
        LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR
        LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' OR
        LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%' OR
        LOWER(p.drug) LIKE '%pramlintide%'
),
med_usage_periods AS (
    -- Step 4: Determine if a medication was used in the first 72h or final 24h
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        antidiabetic_class,
        -- Check for overlap with the 'first 72 hours' window [admittime, admittime + 72h]
        (starttime <= admittime + INTERVAL '72' HOUR AND stoptime >= admittime) AS used_in_first_72h,
        -- Check for overlap with the 'final 24 hours' window [dischtime - 24h, dischtime]
        (starttime <= dischtime AND stoptime >= dischtime - INTERVAL '24' HOUR) AS used_in_final_24h
    FROM
        meds_with_classes
    WHERE antidiabetic_class IS NOT NULL -- Exclude medications that didn't match an antidiabetic class
),
admission_class_usage AS (
    -- Step 5: Aggregate to determine if an antidiabetic class was used for a given admission in each period
    SELECT
        subject_id,
        hadm_id,
        antidiabetic_class,
        MAX(CASE WHEN used_in_first_72h THEN 1 ELSE 0 END) AS used_first_72h,
        MAX(CASE WHEN used_in_final_24h THEN 1 ELSE 0 END) AS used_final_24h
    FROM
        med_usage_periods
    GROUP BY
        subject_id,
        hadm_id,
        antidiabetic_class
),
cohort_total_admissions AS (
    -- Step 6: Calculate the total number of unique admissions in the final cohort
    SELECT COUNT(DISTINCT CONCAT(subject_id, '_', hadm_id)) AS total_cohort_adms
    FROM cohort
)
-- Step 7: Calculate the percentages for each antidiabetic class in both periods
SELECT
    acu.antidiabetic_class,
    ROUND((SUM(acu.used_first_72h) / (SELECT total_cohort_adms FROM cohort_total_admissions)) * 100, 2) AS percentage_first_72h,
    ROUND((SUM(acu.used_final_24h) / (SELECT total_cohort_adms FROM cohort_total_admissions)) * 100, 2) AS percentage_final_24h
FROM
    admission_class_usage acu
GROUP BY
    acu.antidiabetic_class
ORDER BY
    acu.antidiabetic_class;