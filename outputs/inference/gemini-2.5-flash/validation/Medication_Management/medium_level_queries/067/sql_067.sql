WITH TargetCohort AS (
    -- Step 1: Identify eligible patients based on demographics and admission type
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M' -- Male patients
        AND pat.anchor_age BETWEEN 64 AND 74 -- Aged 64-74
        AND ad.admission_type = 'INPATIENT' -- Inpatient admissions
),
PatientDiagnoses AS (
    -- Step 2: Filter admissions to include only those with both Diabetes and Acute Heart Failure diagnoses
    SELECT
        tc.subject_id,
        tc.hadm_id,
        tc.admittime,
        tc.dischtime
    FROM
        TargetCohort tc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dg
        ON tc.subject_id = dg.subject_id AND tc.hadm_id = dg.hadm_id
    GROUP BY
        tc.subject_id, tc.hadm_id, tc.admittime, tc.dischtime
    HAVING
        -- Check for presence of Diabetes (ICD-9: 250.xx, ICD-10: E11.xx for Type 2)
        MAX(CASE WHEN (dg.icd_version = 9 AND dg.icd_code LIKE '250%') OR (dg.icd_version = 10 AND dg.icd_code LIKE 'E11%') THEN 1 ELSE 0 END) = 1
        -- Check for presence of Heart Failure (ICD-9: 428.xx, ICD-10: I50.xx)
        AND MAX(CASE WHEN (dg.icd_version = 9 AND dg.icd_code LIKE '428%') OR (dg.icd_version = 10 AND dg.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) = 1
),
MedicationPrescriptions AS (
    -- Step 3: Extract and classify antidiabetic medications for the identified cohort
    SELECT
        pd.hadm_id,
        pd.admittime,
        pd.dischtime,
        pr.starttime,
        LOWER(pr.drug) AS drug_lower,
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
            WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
            WHEN LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%' THEN 'GLP-1 receptor agonists'
            WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'TZDs'
            ELSE NULL
        END AS drug_class
    FROM
        PatientDiagnoses pd
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON pd.subject_id = pr.subject_id AND pd.hadm_id = pr.hadm_id
    WHERE
        pr.starttime IS NOT NULL -- Ensure a valid starttime for comparison
        AND pr.drug IS NOT NULL -- Ensure drug name is present
        -- Filter early for performance, only considering specific drug keywords
        AND (
            LOWER(pr.drug) LIKE '%insulin%' OR
            LOWER(pr.drug) LIKE '%metformin%' OR
            LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR
            LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR
            LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' OR
            LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%' OR
            LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%'
        )
),
InitiationFlags AS (
    -- Step 4: Determine if a drug class was initiated within the specified time windows for each admission
    SELECT
        mp.hadm_id,
        mp.drug_class,
        -- Check for initiation in the first 12 hours
        MAX(CASE
            WHEN mp.starttime BETWEEN mp.admittime AND DATETIME_ADD(mp.admittime, INTERVAL 12 HOUR)
            THEN 1 ELSE 0 END
        ) AS initiated_12h,
        -- Check for initiation in the final 48 hours
        MAX(CASE
            -- Ensure dischtime is not null and the window is valid
            WHEN mp.dischtime IS NOT NULL AND mp.starttime BETWEEN DATETIME_SUB(mp.dischtime, INTERVAL 48 HOUR) AND mp.dischtime
            THEN 1 ELSE 0 END
        ) AS initiated_48h
    FROM
        MedicationPrescriptions mp
    WHERE
        mp.drug_class IS NOT NULL -- Only consider classified antidiabetic drugs
    GROUP BY
        mp.hadm_id, mp.drug_class
),
CohortSummary AS (
    -- Calculate total number of admissions in the target cohort
    SELECT
        COUNT(DISTINCT hadm_id) AS total_cohort_admissions
    FROM
        PatientDiagnoses
)
-- Step 5: Calculate initiation percentages
SELECT
    init.drug_class,
    SUM(init.initiated_12h) AS admissions_with_initiation_12h,
    (SUM(init.initiated_12h) * 100.0 / cs.total_cohort_admissions) AS percentage_initiated_12h,
    SUM(init.initiated_48h) AS admissions_with_initiation_48h,
    (SUM(init.initiated_48h) * 100.0 / cs.total_cohort_admissions) AS percentage_initiated_48h
FROM
    InitiationFlags init, CohortSummary cs -- Cartesian join as CohortSummary has only one row
GROUP BY
    init.drug_class, cs.total_cohort_admissions
ORDER BY
    init.drug_class;