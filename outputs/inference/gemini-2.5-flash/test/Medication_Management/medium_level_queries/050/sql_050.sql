WITH cohort AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Calculate end of first 24 hours
        DATETIME_ADD(ad.admittime, INTERVAL 24 HOUR) AS first_24h_end, -- Use DATETIME_ADD for BigQuery
        -- Calculate start of final 48 hours
        -- Use GREATEST to handle admissions shorter than 48 hours,
        -- ensuring the period does not start before admittime.
        GREATEST(ad.admittime, DATETIME_SUB(ad.dischtime, INTERVAL 48 HOUR)) AS final_48h_start -- Use DATETIME_SUB for BigQuery
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
        -- Patients must have Type 2 Diabetes Mellitus (T2DM)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_t2dm
            WHERE
                di_t2dm.subject_id = ad.subject_id
                AND di_t2dm.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for T2DM (e.g., 250.xx)
                    (di_t2dm.icd_version = 9 AND di_t2dm.icd_code LIKE '250.%')
                    OR
                    -- ICD-10 codes for T2DM (e.g., E11.xx)
                    (di_t2dm.icd_version = 10 AND di_t2dm.icd_code LIKE 'E11%')
                )
        )
        -- Patients must have Heart Failure (HF)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_hf
            WHERE
                di_hf.subject_id = ad.subject_id
                AND di_hf.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for HF (e.g., 428.xx)
                    (di_hf.icd_version = 9 AND di_hf.icd_code LIKE '428.%')
                    OR
                    -- ICD-10 codes for HF (e.g., I50.xx)
                    (di_hf.icd_version = 10 AND di_hf.icd_code LIKE 'I50%')
                )
        )
),
-- Define the distinct medication classes we are interested in.
distinct_med_classes AS (
    SELECT 'Antidiabetic' AS medication_class UNION ALL
    SELECT 'Beta-Blocker' AS medication_class UNION ALL
    SELECT 'ACEi/ARB/ARNI' AS medication_class UNION ALL
    SELECT 'Loop Diuretic' AS medication_class
),
-- Create a complete set of all cohort members paired with all medication classes.
-- This ensures that even if a patient did not receive a particular drug, they are
-- still accounted for in the medication class-specific analysis (e.g., 0% usage).
all_cohort_med_combos AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.first_24h_end,
        c.final_48h_start,
        dmc.medication_class
    FROM cohort c
    CROSS JOIN distinct_med_classes dmc
),
-- Classify all relevant prescriptions into our defined medication classes.
classified_prescriptions AS (
    SELECT
        pr.subject_id,
        pr.hadm_id,
        pr.starttime,
        CASE
            -- Antidiabetic medications
            WHEN LOWER(pr.drug) LIKE '%insulin%'
              OR LOWER(pr.drug) LIKE '%metformin%'
              OR LOWER(pr.drug) LIKE '%glipizide%'
              OR LOWER(pr.drug) LIKE '%glyburide%'
              OR LOWER(pr.drug) LIKE '%sitagliptin%'
              OR LOWER(pr.drug) LIKE '%empagliflozin%'
              OR LOWER(pr.drug) LIKE '%liraglutide%'
              OR LOWER(pr.drug) LIKE '%glimepiride%'
              OR LOWER(pr.drug) LIKE '%repaglinide%'
              OR LOWER(pr.drug) LIKE '%saxagliptin%'
              OR LOWER(pr.drug) LIKE '%linagliptin%'
              OR LOWER(pr.drug) LIKE '%canagliflozin%'
              OR LOWER(pr.drug) LIKE '%dapagliflozin%'
              OR LOWER(pr.drug) LIKE '%dulaglutide%'
              OR LOWER(pr.drug) LIKE '%exenatide%'
              OR LOWER(pr.drug) LIKE '%acarbose%'
              OR LOWER(pr.drug) LIKE '%miglitol%'
              OR LOWER(pr.drug) LIKE '%pioglitazone%'
              OR LOWER(pr.drug) LIKE '%rosiglitazone%'
              THEN 'Antidiabetic'
            -- Beta-Blocker medications
            WHEN LOWER(pr.drug) LIKE '%metoprolol%'
              OR LOWER(pr.drug) LIKE '%carvedilol%'
              OR LOWER(pr.drug) LIKE '%atenolol%'
              OR LOWER(pr.drug) LIKE '%bisoprolol%'
              OR LOWER(pr.drug) LIKE '%propranolol%'
              OR LOWER(pr.drug) LIKE '%labetalol%'
              OR LOWER(pr.drug) LIKE '%sotalol%'
              OR LOWER(pr.drug) LIKE '%nadolol%'
              OR LOWER(pr.drug) LIKE '%timolol%'
              OR LOWER(pr.drug) LIKE '%esmolol%'
            THEN 'Beta-Blocker'
            -- ACEi/ARB/ARNI medications
            WHEN (LOWER(pr.drug) LIKE '%pril%' AND LOWER(pr.drug) NOT LIKE '%epinephrine%') -- ACE inhibitors
              OR LOWER(pr.drug) LIKE '%sartan%' -- ARBs
              OR LOWER(pr.drug) LIKE '%sacubitril%' -- ARNIs
            THEN 'ACEi/ARB/ARNI'
            -- Loop Diuretic medications
            WHEN LOWER(pr.drug) LIKE '%furosemide%'
              OR LOWER(pr.drug) LIKE '%bumetanide%'
              OR LOWER(pr.drug) LIKE '%torsemide%'
            THEN 'Loop Diuretic'
            ELSE NULL
        END AS medication_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.drug IS NOT NULL AND pr.starttime IS NOT NULL
),
-- For each HADM_ID in the cohort and each medication class,
-- determine if the medication was prescribed in the first 24h and/or final 48h.
patient_med_status AS (
    SELECT
        acmc.subject_id,
        acmc.hadm_id,
        acmc.medication_class,
        -- Check if medication was prescribed in the first 24 hours
        MAX(CASE
            WHEN cp.starttime IS NOT NULL
             AND cp.starttime >= acmc.admittime
             AND cp.starttime <= acmc.first_24h_end
            THEN 1 ELSE 0 END) AS on_first_24h,
        -- Check if medication was prescribed in the final 48 hours
        MAX(CASE
            WHEN cp.starttime IS NOT NULL
             AND cp.starttime >= acmc.final_48h_start
             AND cp.starttime <= acmc.dischtime
            THEN 1 ELSE 0 END) AS on_final_48h
    FROM all_cohort_med_combos acmc
    LEFT JOIN classified_prescriptions cp
        ON acmc.subject_id = cp.subject_id
       AND acmc.hadm_id = cp.hadm_id
       AND acmc.medication_class = cp.medication_class
    GROUP BY acmc.subject_id, acmc.hadm_id, acmc.medication_class
),
-- Aggregate the counts for each medication class across the cohort
med_changes_summary AS (
    SELECT
        pms.medication_class,
        SUM(pms.on_first_24h) AS num_on_first_24h,
        SUM(pms.on_final_48h) AS num_on_final_48h,
        -- Count patients who were on medication in both periods
        SUM(CASE WHEN pms.on_first_24h = 1 AND pms.on_final_48h = 1 THEN 1 ELSE 0 END) AS num_continued,
        -- Count patients who initiated medication (on final 48h but not first 24h)
        SUM(CASE WHEN pms.on_first_24h = 0 AND pms.on_final_48h = 1 THEN 1 ELSE 0 END) AS num_initiated,
        -- Count patients who discontinued medication (on first 24h but not final 48h)
        SUM(CASE WHEN pms.on_first_24h = 1 AND pms.on_final_48h = 0 THEN 1 ELSE 0 END) AS num_discontinued
    FROM patient_med_status pms
    GROUP BY pms.medication_class
)
-- Final selection with calculated percentages
SELECT
    mcs.medication_class,
    SAFE_DIVIDE(mcs.num_on_first_24h * 100.0, (SELECT COUNT(DISTINCT subject_id || '_' || hadm_id) FROM cohort)) AS percent_on_first_24h,
    SAFE_DIVIDE(mcs.num_on_final_48h * 100.0, (SELECT COUNT(DISTINCT subject_id || '_' || hadm_id) FROM cohort)) AS percent_on_final_48h,
    mcs.num_continued,
    mcs.num_initiated,
    mcs.num_discontinued
FROM med_changes_summary mcs
ORDER BY mcs.medication_class;