with diabetes and acute heart failure, among inpatients aged 71–81,
-- report initiation rates (%) for metformin, sulfonylureas, DPP-4, SGLT2, thiazolidinediones: first 72h vs last 48h.

WITH
-- Step 1: Define the cohort of patients aged 71-81 with acute heart failure AND diabetes.
cohort AS (
    SELECT DISTINCT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        pat.anchor_age BETWEEN 71 AND 81
        AND (
            LOWER(d_dx.long_title) LIKE '%acute heart failure%'
            OR LOWER(d_dx.long_title) LIKE '%acute on chronic%heart failure%'
        )
        -- Add filter for diabetes diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diab_dx
            WHERE diab_dx.hadm_id = adm.hadm_id
            AND (
                (diab_dx.icd_version = 9 AND diab_dx.icd_code LIKE '250%')
                OR (diab_dx.icd_version = 10 AND REGEXP_CONTAINS(diab_dx.icd_code, r'^E0[8-9]|^E1[013]'))
            )
        )
),

-- Step 2: Get all prescriptions for the cohort.
cohort_prescriptions AS (
    SELECT
        co.hadm_id,
        co.admittime,
        co.dischtime,
        pr.starttime,
        pr.drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN cohort AS co ON pr.hadm_id = co.hadm_id
    WHERE pr.starttime IS NOT NULL
),

-- Step 3: Classify prescriptions into drug classes. This handles combination pills.
classified_prescriptions AS (
    SELECT hadm_id, admittime, dischtime, starttime, 'Metformin' AS drug_class
    FROM cohort_prescriptions WHERE LOWER(drug) LIKE '%metformin%'
    UNION ALL
    SELECT hadm_id, admittime, dischtime, starttime, 'Sulfonylureas' AS drug_class
    FROM cohort_prescriptions WHERE LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%'
    UNION ALL
    SELECT hadm_id, admittime, dischtime, starttime, 'DPP-4 Inhibitors' AS drug_class
    FROM cohort_prescriptions WHERE LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%'
    UNION ALL
    SELECT hadm_id, admittime, dischtime, starttime, 'SGLT2 Inhibitors' AS drug_class
    FROM cohort_prescriptions WHERE LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%ertugliflozin%'
    UNION ALL
    SELECT hadm_id, admittime, dischtime, starttime, 'Thiazolidinediones' AS drug_class
    FROM cohort_prescriptions WHERE LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
),

-- Step 4: Find the first prescription (initiation) for each patient and drug class.
first_prescriptions AS (
    SELECT
        hadm_id,
        admittime,
        dischtime,
        drug_class,
        MIN(starttime) AS initiation_time
    FROM classified_prescriptions
    GROUP BY hadm_id, admittime, dischtime, drug_class
),

-- Step 5: Count the number of patients initiated in each window for each drug class.
initiation_counts AS (
    SELECT
        drug_class,
        COUNT(DISTINCT CASE WHEN initiation_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN hadm_id END) AS initiated_first_72h,
        COUNT(DISTINCT CASE WHEN initiation_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND initiation_time <= dischtime THEN hadm_id END) AS initiated_last_48h
    FROM first_prescriptions
    GROUP BY drug_class
),

-- Step 6: Create a scaffold of all drug classes to ensure all are included in the final report.
all_drug_classes AS (
    SELECT 'Metformin' AS drug_class UNION ALL
    SELECT 'Sulfonylureas' UNION ALL
    SELECT 'DPP-4 Inhibitors' UNION ALL
    SELECT 'SGLT2 Inhibitors' UNION ALL
    SELECT 'Thiazolidinediones'
)

-- Final Step: Calculate rates and present the final report.
SELECT
    adc.drug_class,
    SAFE_DIVIDE(COALESCE(ic.initiated_first_72h, 0) * 100.0, total_patients.total_count) AS initiation_rate_first_72h_pct,
    SAFE_DIVIDE(COALESCE(ic.initiated_last_48h, 0) * 100.0, total_patients.total_count) AS initiation_rate_last_48h_pct
FROM all_drug_classes AS adc
LEFT JOIN initiation_counts AS ic ON adc.drug_class = ic.drug_class
CROSS JOIN (SELECT COUNT(DISTINCT hadm_id) AS total_count FROM cohort) AS total_patients
ORDER BY
    CASE adc.drug_class
        WHEN 'Metformin' THEN 1
        WHEN 'Sulfonylureas' THEN 2
        WHEN 'DPP-4 Inhibitors' THEN 3
        WHEN 'SGLT2 Inhibitors' THEN 4
        WHEN 'Thiazolidinediones' THEN 5
    END;