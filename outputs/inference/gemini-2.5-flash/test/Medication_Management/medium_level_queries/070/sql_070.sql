WITH PatientsCohort AS (
    -- Step 1: Identify eligible female inpatients aged 68-78 with a valid discharge time
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
        AND ad.dischtime IS NOT NULL -- Ensure admission has a dischtime for "last 12h" calculation
),
PatientsWithT2DM AS (
    -- Step 2: Filter for patients with Type 2 Diabetes Mellitus (T2DM)
    SELECT DISTINCT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.dischtime
    FROM
        PatientsCohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pc.hadm_id = di.hadm_id
    WHERE
        (
            (di.icd_version = 9 AND (
                di.icd_code LIKE '250.0%'  -- T2DM without mention of complication
                OR di.icd_code LIKE '250.2%'  -- T2DM with ketoacidosis
                OR di.icd_code LIKE '250.4%'  -- T2DM with renal manifestations
                OR di.icd_code LIKE '250.6%'  -- T2DM with neurological manifestations
                OR di.icd_code LIKE '250.8%'  -- T2DM with other specified complications
                OR di.icd_code LIKE '250.9%'  -- T2DM with unspecified complications
            ))
            OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%') -- Type 2 diabetes mellitus (ICD-10)
        )
),
PatientsWithHF AS (
    -- Step 3: Filter for patients with Heart Failure (HF)
    SELECT DISTINCT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.dischtime
    FROM
        PatientsCohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pc.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%') -- Heart Failure (ICD-9)
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- Heart Failure (ICD-10)
),
FinalCohort AS (
    -- Step 4: Combine T2DM and HF patients to form the final cohort
    SELECT DISTINCT
        t2dm.subject_id,
        t2dm.hadm_id,
        t2dm.admittime,
        t2dm.dischtime
    FROM
        PatientsWithT2DM t2dm
    INNER JOIN
        PatientsWithHF hf
        ON t2dm.subject_id = hf.subject_id AND t2dm.hadm_id = hf.hadm_id
),
total_cohort_count AS (
    -- Step 5: Get the total number of unique patients in the final cohort
    SELECT
        COUNT(DISTINCT subject_id) AS total_patients
    FROM
        FinalCohort
),
PrescriptionsClassified AS (
    -- Step 6: Identify relevant prescriptions and classify them into drug classes
    SELECT
        fc.subject_id,
        fc.hadm_id,
        pr.starttime,
        pr.stoptime,
        fc.admittime,
        fc.dischtime,
        CASE
            WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
            WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
            ELSE NULL -- Exclude other drugs from analysis
        END AS drug_class
    FROM
        FinalCohort fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON fc.subject_id = pr.subject_id AND fc.hadm_id = pr.hadm_id
    WHERE
        -- Filter only for drugs of interest to optimize performance
        LOWER(pr.drug) LIKE '%metformin%'
        OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%'
        OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
        OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%'
),
DrugExposureWindows AS (
    -- Step 7: Determine if a drug was administered/active in the first 48 hours or last 12 hours
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.drug_class,
        -- Check if drug was active in the first 48 hours of admission
        MAX(CASE
            WHEN pc.starttime <= DATETIME_ADD(pc.admittime, INTERVAL 48 HOUR)
            AND (pc.stoptime IS NULL OR pc.stoptime >= pc.admittime)
            THEN 1 ELSE 0
        END) AS in_first_48h,
        -- Check if drug was active in the last 12 hours of admission
        MAX(CASE
            WHEN pc.stoptime >= DATETIME_SUB(pc.dischtime, INTERVAL 12 HOUR)
            AND (pc.starttime IS NULL OR pc.starttime <= pc.dischtime)
            THEN 1 ELSE 0
        END) AS in_last_12h
    FROM
        PrescriptionsClassified pc
    WHERE
        pc.drug_class IS NOT NULL -- Ensure only classified drugs are considered
    GROUP BY
        pc.subject_id, pc.hadm_id, pc.drug_class
),
prevalence_metrics AS (
    -- Step 8: Calculate the count of unique patients exposed to each drug class in the specified windows
    SELECT
        de.drug_class,
        COUNT(DISTINCT CASE WHEN de.in_first_48h = 1 THEN de.subject_id END) AS count_first_48h,
        COUNT(DISTINCT CASE WHEN de.in_last_12h = 1 THEN de.subject_id END) AS count_last_12h
    FROM
        DrugExposureWindows de
    GROUP BY
        de.drug_class
)
-- Step 9: Final calculation - prevalence percentages and net change
SELECT
    pm.drug_class,
    ROUND((SAFE_DIVIDE(pm.count_first_48h * 100.0, tcc.total_patients)), 2) AS prevalence_first_48h_pct,
    ROUND((SAFE_DIVIDE(pm.count_last_12h * 100.0, tcc.total_patients)), 2) AS prevalence_last_12h_pct,
    ROUND((SAFE_DIVIDE(pm.count_last_12h * 100.0, tcc.total_patients) - SAFE_DIVIDE(pm.count_first_48h * 100.0, tcc.total_patients)), 2) AS net_percentage_point_change
FROM
    prevalence_metrics pm
CROSS JOIN
    total_cohort_count tcc
ORDER BY
    pm.drug_class;