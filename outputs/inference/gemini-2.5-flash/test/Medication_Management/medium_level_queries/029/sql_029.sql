WITH CohortAdmissions AS (
    -- Step 1: Define the target cohort of admissions
    -- Filter for female patients aged 69-79 with T2DM and Heart Failure
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Calculate the end time of the first 72 hours of admission
        TIMESTAMP_ADD(ad.admittime, INTERVAL 72 HOUR) AS first_72h_end_time,
        -- Calculate the start time of the last 72 hours of admission
        -- Ensure it doesn't go before admittime if the stay is shorter than 72 hours
        GREATEST(ad.admittime, TIMESTAMP_SUB(ad.dischtime, INTERVAL 72 HOUR)) AS last_72h_start_time
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 69 AND 79
        -- Ensure the admission has a diagnosis of Type 2 Diabetes Mellitus
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'E11%') -- ICD-10 for Type 2 Diabetes Mellitus (E11.x)
                    OR (di.icd_version = 9 AND di.icd_code LIKE '250.%' AND SUBSTR(di.icd_code, 6, 1) IN ('0', '2')) -- ICD-9 for Type 2 Diabetes (250.x0 or 250.x2)
                )
        )
        -- Ensure the admission has a diagnosis of Heart Failure
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 for Heart Failure (I50.x)
                    OR (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 for Heart Failure (428.x)
                )
        )
),
CohortPrescriptions AS (
    -- Step 2: Identify and categorize selected drug prescriptions for the cohort
    SELECT
        ca.subject_id,
        ca.hadm_id,
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
            WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitor'
            WHEN LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' THEN 'SGLT2 Inhibitor'
            WHEN LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' THEN 'GLP-1 Agonist'
            WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'TZD'
            ELSE 'Other' -- Should mostly be filtered out by the WHERE clause below
        END AS drug_class,
        -- Flag if the prescription starttime falls within the first 72 hours
        (pr.starttime >= ca.admittime AND pr.starttime < ca.first_72h_end_time) AS in_first_72h,
        -- Flag if the prescription starttime falls within the last 72 hours
        (pr.starttime >= ca.last_72h_start_time AND pr.starttime < ca.dischtime) AS in_last_72h
    FROM
        CohortAdmissions AS ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions AS pr
        ON ca.subject_id = pr.subject_id AND ca.hadm_id = pr.hadm_id
    WHERE
        pr.starttime IS NOT NULL
        AND pr.starttime >= ca.admittime AND pr.starttime < ca.dischtime -- Ensure prescription is within admission
        AND (
            LOWER(pr.drug) LIKE '%insulin%' OR
            LOWER(pr.drug) LIKE '%metformin%' OR
            LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR
            LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR
            LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR
            LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' OR
            LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%'
        )
),
AdmissionDrugExposure AS (
    -- Step 3: Determine for each admission which drug classes were received in each time window
    SELECT
        hadm_id,
        MAX(CASE WHEN drug_class = 'Insulin' AND in_first_72h THEN 1 ELSE 0 END) AS received_insulin_first_72h,
        MAX(CASE WHEN drug_class = 'Metformin' AND in_first_72h THEN 1 ELSE 0 END) AS received_metformin_first_72h,
        MAX(CASE WHEN drug_class = 'Sulfonylurea' AND in_first_72h THEN 1 ELSE 0 END) AS received_sulfonylurea_first_72h,
        MAX(CASE WHEN drug_class = 'DPP-4 Inhibitor' AND in_first_72h THEN 1 ELSE 0 END) AS received_dpp4_first_72h,
        MAX(CASE WHEN drug_class = 'SGLT2 Inhibitor' AND in_first_72h THEN 1 ELSE 0 END) AS received_sglt2_first_72h,
        MAX(CASE WHEN drug_class = 'GLP-1 Agonist' AND in_first_72h THEN 1 ELSE 0 END) AS received_glp1_first_72h,
        MAX(CASE WHEN drug_class = 'TZD' AND in_first_72h THEN 1 ELSE 0 END) AS received_tzd_first_72h,

        MAX(CASE WHEN drug_class = 'Insulin' AND in_last_72h THEN 1 ELSE 0 END) AS received_insulin_last_72h,
        MAX(CASE WHEN drug_class = 'Metformin' AND in_last_72h THEN 1 ELSE 0 END) AS received_metformin_last_72h,
        MAX(CASE WHEN drug_class = 'Sulfonylurea' AND in_last_72h THEN 1 ELSE 0 END) AS received_sulfonylurea_last_72h,
        MAX(CASE WHEN drug_class = 'DPP-4 Inhibitor' AND in_last_72h THEN 1 ELSE 0 END) AS received_dpp4_last_72h,
        MAX(CASE WHEN drug_class = 'SGLT2 Inhibitor' AND in_last_72h THEN 1 ELSE 0 END) AS received_sglt2_last_72h,
        MAX(CASE WHEN drug_class = 'GLP-1 Agonist' AND in_last_72h THEN 1 ELSE 0 END) AS received_glp1_last_72h,
        MAX(CASE WHEN drug_class = 'TZD' AND in_last_72h THEN 1 ELSE 0 END) AS received_tzd_last_72h
    FROM
        CohortPrescriptions
    GROUP BY
        hadm_id
)
-- Step 4: Calculate final percentages
SELECT
    'Target Cohort (Admissions)' AS CohortDescription,
    COUNT(ca.hadm_id) AS TotalAdmissionsInCohort,

    -- Percentages for First 72 Hours
    ROUND(COALESCE(SUM(ade.received_insulin_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Insulin_First_72h,
    ROUND(COALESCE(SUM(ade.received_metformin_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Metformin_First_72h,
    ROUND(COALESCE(SUM(ade.received_sulfonylurea_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Sulfonylurea_First_72h,
    ROUND(COALESCE(SUM(ade.received_dpp4_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_DPP4_First_72h,
    ROUND(COALESCE(SUM(ade.received_sglt2_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_SGLT2_First_72h,
    ROUND(COALESCE(SUM(ade.received_glp1_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_GLP1_First_72h,
    ROUND(COALESCE(SUM(ade.received_tzd_first_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_TZD_First_72h,

    -- Percentages for Last 72 Hours
    ROUND(COALESCE(SUM(ade.received_insulin_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Insulin_Last_72h,
    ROUND(COALESCE(SUM(ade.received_metformin_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Metformin_Last_72h,
    ROUND(COALESCE(SUM(ade.received_sulfonylurea_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_Sulfonylurea_Last_72h,
    ROUND(COALESCE(SUM(ade.received_dpp4_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_DPP4_Last_72h,
    ROUND(COALESCE(SUM(ade.received_sglt2_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_SGLT2_Last_72h,
    ROUND(COALESCE(SUM(ade.received_glp1_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_GLP1_Last_72h,
    ROUND(COALESCE(SUM(ade.received_tzd_last_72h), 0) * 100.0 / COUNT(ca.hadm_id), 2) AS Percent_TZD_Last_72h

FROM
    CohortAdmissions AS ca
LEFT JOIN
    AdmissionDrugExposure AS ade
    ON ca.hadm_id = ade.hadm_id;