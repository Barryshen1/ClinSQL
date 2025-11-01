WITH T2DM_diagnoses AS (
    -- Identify admissions with Type 2 Diabetes Mellitus (T2DM) diagnoses
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_version = 9 AND icd_code LIKE '250.%' AND SUBSTR(icd_code, 4, 1) NOT IN ('1', '3')) -- ICD-9 for T2DM, excluding Type 1 (250.1) and other specified (250.3)
        OR (icd_version = 10 AND icd_code LIKE 'E11%') -- ICD-10 for T2DM
),
HF_diagnoses AS (
    -- Identify admissions with Heart Failure (HF) diagnoses
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_version = 9 AND icd_code LIKE '428%') -- ICD-9 for Heart Failure
        OR (icd_version = 10 AND icd_code LIKE 'I50%') -- ICD-10 for Heart Failure
),
cohort AS (
    -- Define the target patient cohort: male, 36-46 years old, with T2DM and HF
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        CAST(ad.admittime AS TIMESTAMP) AS admittime, -- Explicit cast to TIMESTAMP
        CAST(ad.dischtime AS TIMESTAMP) AS dischtime  -- Explicit cast to TIMESTAMP
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 36 AND 46
        -- Ensure the admission has both T2DM and HF diagnoses
        AND EXISTS (SELECT 1 FROM T2DM_diagnoses t2dm WHERE t2dm.hadm_id = ad.hadm_id)
        AND EXISTS (SELECT 1 FROM HF_diagnoses hf WHERE hf.hadm_id = ad.hadm_id)
),
antidiabetic_med_classes AS (
    -- Assign antidiabetic medications from emar to their respective drug classes
    SELECT
        c.subject_id,
        c.hadm_id,
        CAST(em.charttime AS TIMESTAMP) AS charttime, -- Explicit cast to TIMESTAMP
        CASE
            WHEN LOWER(em.medication) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(em.medication) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(em.medication) LIKE '%glipizide%' OR LOWER(em.medication) LIKE '%glyburide%' OR LOWER(em.medication) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(em.medication) LIKE '%sitagliptin%' OR LOWER(em.medication) LIKE '%saxagliptin%' OR LOWER(em.medication) LIKE '%linagliptin%' OR LOWER(em.medication) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
            WHEN LOWER(em.medication) LIKE '%canagliflozin%' OR LOWER(em.medication) LIKE '%dapagliflozin%' OR LOWER(em.medication) LIKE '%empagliflozin%' OR LOWER(em.medication) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
            WHEN LOWER(em.medication) LIKE '%liraglutide%' OR LOWER(em.medication) LIKE '%exenatide%' OR LOWER(em.medication) LIKE '%semaglutide%' OR LOWER(em.medication) LIKE '%dulaglutide%' OR LOWER(em.medication) LIKE '%tirzepatide%' THEN 'GLP-1 Receptor Agonists'
            WHEN LOWER(em.medication) LIKE '%pioglitazone%' OR LOWER(em.medication) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones (TZDs)'
            WHEN LOWER(em.medication) LIKE '%repaglinide%' OR LOWER(em.medication) LIKE '%nateglinide%' THEN 'Meglitinides'
            WHEN LOWER(em.medication) LIKE '%acarbose%' OR LOWER(em.medication) LIKE '%miglitol%' THEN 'Alpha-glucosidase inhibitors'
            ELSE NULL -- Exclude medications that don't match any antidiabetic class
        END AS drug_class
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.emar em
        ON c.subject_id = em.subject_id AND c.hadm_id = em.hadm_id
    WHERE
        em.medication IS NOT NULL
        AND em.charttime IS NOT NULL -- Ensure valid charttime for temporal analysis
),
min_charttime_per_class AS (
    -- Find the earliest administration time for each antidiabetic drug class per admission
    SELECT
        fa.subject_id,
        fa.hadm_id,
        fa.drug_class,
        fa.charttime AS first_admin_charttime,
        c.admittime,
        c.dischtime
    FROM (
        SELECT
            subject_id,
            hadm_id,
            charttime,
            drug_class,
            ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, drug_class ORDER BY charttime) AS rn
        FROM antidiabetic_med_classes
        WHERE drug_class IS NOT NULL
    ) fa
    INNER JOIN cohort c
        ON fa.subject_id = c.subject_id AND fa.hadm_id = c.hadm_id
    WHERE fa.rn = 1 -- Select only the first administration
),
window_assignments AS (
    -- Assign each first administration to the specified time windows by creating unique admission IDs
    SELECT
        subject_id,
        hadm_id,
        drug_class,
        first_admin_charttime,
        admittime,
        dischtime,
        -- Generate a unique string for (subject_id, hadm_id) if initiated in the first 12 hours
        CASE
            WHEN first_admin_charttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN CONCAT(CAST(subject_id AS STRING), '-', CAST(hadm_id AS STRING))
            ELSE NULL
        END AS initiated_first_12h_id,
        -- Generate a unique string for (subject_id, hadm_id) if initiated in the final 48 hours
        CASE
            WHEN first_admin_charttime BETWEEN
                GREATEST(admittime, TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR))
                AND dischtime THEN CONCAT(CAST(subject_id AS STRING), '-', CAST(hadm_id AS STRING))
            ELSE NULL
        END AS initiated_final_48h_id
    FROM min_charttime_per_class
),
total_cohort_count AS (
    -- Calculate the total number of distinct admissions in the cohort once
    SELECT COUNT(DISTINCT CONCAT(CAST(subject_id AS STRING), '-', CAST(hadm_id AS STRING))) AS total_admissions
    FROM cohort
)
-- Calculate initiation rates and net change
SELECT
    wa.drug_class,
    -- Count distinct patient admissions initiating the drug class in the first 12 hours
    COUNT(DISTINCT wa.initiated_first_12h_id) AS cohort_initiated_first_12h_count,
    -- Count distinct patient admissions initiating the drug class in the final 48 hours
    COUNT(DISTINCT wa.initiated_final_48h_id) AS cohort_initiated_final_48h_count,
    -- Calculate initiation rate for the first 12 hours as a percentage
    (COUNT(DISTINCT wa.initiated_first_12h_id) * 100.0 / ANY_VALUE(tc.total_admissions)) AS initiation_rate_first_12h_percent,
    -- Calculate initiation rate for the final 48 hours as a percentage
    (COUNT(DISTINCT wa.initiated_final_48h_id) * 100.0 / ANY_VALUE(tc.total_admissions)) AS initiation_rate_final_48h_percent,
    -- Calculate net change in percentage points (final_48h_percent - first_12h_percent)
    ((COUNT(DISTINCT wa.initiated_final_48h_id) * 100.0 / ANY_VALUE(tc.total_admissions)) -
     (COUNT(DISTINCT wa.initiated_first_12h_id) * 100.0 / ANY_VALUE(tc.total_admissions))) AS net_change_pp
FROM window_assignments wa
CROSS JOIN total_cohort_count tc -- Join with the pre-calculated total cohort count
GROUP BY wa.drug_class
ORDER BY net_change_pp DESC;