WITH patient_cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.gender,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 42 AND 52
        -- Ensure patient has a diabetes diagnosis
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dm
            WHERE
                di_dm.subject_id = adm.subject_id
                AND di_dm.hadm_id = adm.hadm_id
                AND di_dm.icd_version = 9 AND di_dm.icd_code LIKE '250%' -- ICD-9 Diabetes
                UNION ALL
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dm
            WHERE
                 di_dm.subject_id = adm.subject_id
                AND di_dm.hadm_id = adm.hadm_id
                AND di_dm.icd_version = 10 AND SUBSTR(di_dm.icd_code, 1, 3) BETWEEN 'E10' AND 'E14' -- ICD-10 Diabetes (E10-E14)
        )
        -- Ensure patient has an acute heart failure diagnosis
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ahf
            WHERE
                di_ahf.subject_id = adm.subject_id
                AND di_ahf.hadm_id = adm.hadm_id
                 AND di_ahf.icd_version = 9 AND di_ahf.icd_code LIKE '428%' -- ICD-9 Heart Failure (428.xx)
                UNION ALL
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ahf
            WHERE
                 di_ahf.subject_id = adm.subject_id
                AND di_ahf.hadm_id = adm.hadm_id
                 AND di_ahf.icd_version = 10 AND di_ahf.icd_code LIKE 'I50%' -- ICD-10 Heart Failure (I50.xx)
        )
),
-- Step 2: Identify relevant prescriptions for the cohort and assign drug classes
cohort_prescriptions AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.dischtime,
        p.starttime,
        LOWER(p.drug) AS drug_name,
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(glipi|glyburi|glimepiride)') THEN 'Sulfonylurea' -- Sulfonylureas
            WHEN LOWER(p.drug) LIKE '%gliptin%' THEN 'DPP-4' -- DPP-4 Inhibitors (e.g., sitagliptin, saxagliptin)
            WHEN LOWER(p.drug) LIKE '%flozin%' THEN 'SGLT2' -- SGLT2 Inhibitors (e.g., canagliflozin, empagliflozin)
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(glutide|exenatide|dulaglutide|semaglutide|liraglutide)') THEN 'GLP-1' -- GLP-1 Receptor Agonists (e.g., liraglutide, semaglutide, exenatide, dulaglutide)
            WHEN LOWER(p.drug) LIKE '%glitazone%' THEN 'TZD' -- Thiazolidinediones (e.g., pioglitazone, rosiglitazone)
            ELSE NULL
        END AS drug_class
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON pc.subject_id = p.subject_id AND pc.hadm_id = p.hadm_id
    WHERE
        -- Only include prescriptions that fall into one of our target drug classes
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(glipi|glyburi|glimepiride)') THEN 'Sulfonylurea'
            WHEN LOWER(p.drug) LIKE '%gliptin%' THEN 'DPP-4'
            WHEN LOWER(p.drug) LIKE '%flozin%' THEN 'SGLT2'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(glutide|exenatide|dulaglutide|semaglutide|liraglutide)') THEN 'GLP-1'
            WHEN LOWER(p.drug) LIKE '%glitazone%' THEN 'TZD'
            ELSE NULL
        END IS NOT NULL
),
-- Step 3: Determine which drug classes were prescribed in the first 24 hours for each patient/admission
first_24h_meds AS (
    SELECT DISTINCT
        cp.subject_id,
        cp.hadm_id,
        cp.drug_class
    FROM
        cohort_prescriptions cp
    WHERE
        cp.starttime >= cp.admittime
        AND cp.starttime < TIMESTAMP_ADD(cp.admittime, INTERVAL 24 HOUR)
),
-- Step 4: Determine which drug classes were prescribed in the final 12 hours for each patient/admission
final_12h_meds AS (
    SELECT DISTINCT
        cp.subject_id,
        cp.hadm_id,
        cp.drug_class
    FROM
        cohort_prescriptions cp
    WHERE
        cp.dischtime IS NOT NULL -- Ensure dischtime is available for the window calculation
        AND cp.dischtime >= cp.admittime -- Admission must be long enough to have a final 12h window
        AND cp.starttime >= GREATEST(cp.admittime, TIMESTAMP_SUB(cp.dischtime, INTERVAL 12 HOUR)) -- Prescription must be during stay AND in final 12h window
        AND cp.starttime < cp.dischtime
),
-- Step 5: Consolidate prescription information per patient/admission and drug class
patient_drug_exposure AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        dc.class_name AS drug_class,
        MAX(CASE WHEN f24.drug_class IS NOT NULL THEN 1 ELSE 0 END) AS prescribed_in_first_24h,
        MAX(CASE WHEN f12.drug_class IS NOT NULL THEN 1 ELSE 0 END) AS prescribed_in_final_12h
    FROM
        patient_cohort pc
    CROSS JOIN
        (
            -- List all target drug classes to ensure they appear in the final output
            SELECT 'Insulin' AS class_name UNION ALL
            SELECT 'Metformin' UNION ALL
            SELECT 'Sulfonylurea' UNION ALL
            SELECT 'DPP-4' UNION ALL
            SELECT 'SGLT2' UNION ALL
            SELECT 'GLP-1' UNION ALL
            SELECT 'TZD'
        ) AS dc
    LEFT JOIN
        first_24h_meds f24
        ON pc.subject_id = f24.subject_id
        AND pc.hadm_id = f24.hadm_id
        AND dc.class_name = f24.drug_class
    LEFT JOIN
        final_12h_meds f12
        ON pc.subject_id = f12.subject_id
        AND pc.hadm_id = f12.hadm_id
        AND dc.class_name = f12.drug_class
    GROUP BY
        pc.subject_id,
        pc.hadm_id,
        dc.class_name
),
-- Step 6: Calculate total cohort size for prevalence calculation
cohort_size AS (
    SELECT COUNT(DISTINCT subject_id, hadm_id) AS total_admissions
    FROM patient_cohort
)
-- Step 7: Final aggregation and prevalence calculation
SELECT
    pde.drug_class,
    -- Prevalence in first 24 hours
    SAFE_DIVIDE(SUM(pde.prescribed_in_first_24h), cs.total_admissions) * 100 AS prevalence_first_24h_pct,
    -- Prevalence in final 12 hours
    SAFE_DIVIDE(SUM(pde.prescribed_in_final_12h), cs.total_admissions) * 100 AS prevalence_final_12h_pct,
    -- Net change in percentage points (pp)
    (SAFE_DIVIDE(SUM(pde.prescribed_in_final_12h), cs.total_admissions) * 100) -
    (SAFE_DIVIDE(SUM(pde.prescribed_in_first_24h), cs.total_admissions) * 100) AS net_change_pp
FROM
    patient_drug_exposure pde
CROSS JOIN
    cohort_size cs
GROUP BY
    pde.drug_class, cs.total_admissions
ORDER BY
    pde.drug_class;