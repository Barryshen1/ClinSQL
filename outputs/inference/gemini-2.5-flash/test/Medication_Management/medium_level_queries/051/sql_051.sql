WITH AdmissionsCohort AS (
    -- 1. Identify the target patient cohort: females, 86-96, DM, HF
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 86 AND 96
        -- Filter for common inpatient admission types
        AND ad.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE') -- Excludes 'OBSERVATION', 'NEWBORN', etc.
        AND ad.dischtime IS NOT NULL -- Essential for calculating the 'final 72h' window

    -- Check for Diabetes Mellitus (DM) diagnosis (ICD-10 codes E10-E14)
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di_dm
        WHERE di_dm.subject_id = ad.subject_id
            AND di_dm.hadm_id = ad.hadm_id
            AND di_dm.icd_version = 10
            AND di_dm.icd_code LIKE 'E1[0-4]%'
    )
    -- Check for Heart Failure (HF) diagnosis (ICD-10 code I50)
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di_hf
        WHERE di_hf.subject_id = ad.subject_id
            AND di_hf.hadm_id = ad.hadm_id
            AND di_hf.icd_version = 10
            AND di_hf.icd_code LIKE 'I50%'
    )
),
MedicationClassification AS (
    -- 2. Classify prescriptions as Insulin or Oral Agent for diabetes management
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        pr.starttime,
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(pr.drug) LIKE '%metformin%'
                 OR LOWER(pr.drug) LIKE '%glyburide%'
                 OR LOWER(pr.drug) LIKE '%glipizide%'
                 OR LOWER(pr.drug) LIKE '%glimepiride%'
                 OR LOWER(pr.drug) LIKE '%sitagliptin%'
                 OR LOWER(pr.drug) LIKE '%saxagliptin%'
                 OR LOWER(pr.drug) LIKE '%linagliptin%'
                 OR LOWER(pr.drug) LIKE '%canagliflozin%'
                 OR LOWER(pr.drug) LIKE '%dapagliflozin%'
                 OR LOWER(pr.drug) LIKE '%empagliflozin%'
                 OR LOWER(pr.drug) LIKE '%pioglitazone%'
                 OR LOWER(pr.drug) LIKE '%rosiglitazone%'
                 OR LOWER(pr.drug) LIKE '%repaglinide%'
                 OR LOWER(pr.drug) LIKE '%nateglinide%'
                 OR LOWER(pr.drug) LIKE '%acarbose%'
                 OR LOWER(pr.drug) LIKE '%miglitol%'
                 OR LOWER(pr.drug) LIKE '%tolbutamide%'
                 OR LOWER(pr.drug) LIKE '%chlorpropamide%'
                THEN 'Oral Agent'
            ELSE NULL -- Not a classified DM medication
        END AS medication_class
    FROM
        AdmissionsCohort AS ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions AS pr
        ON ac.subject_id = pr.subject_id AND ac.hadm_id = pr.hadm_id
    WHERE
        pr.starttime IS NOT NULL
        AND LOWER(pr.drug) IS NOT NULL -- Ensure drug name exists for classification
        AND (LOWER(pr.drug) LIKE '%insulin%' OR
             LOWER(pr.drug) LIKE '%metformin%' OR
             LOWER(pr.drug) LIKE '%glyburide%' OR
             LOWER(pr.drug) LIKE '%glipizide%' OR
             LOWER(pr.drug) LIKE '%glimepiride%' OR
             LOWER(pr.drug) LIKE '%sitagliptin%' OR
             LOWER(pr.drug) LIKE '%saxagliptin%' OR
             LOWER(pr.drug) LIKE '%linagliptin%' OR
             LOWER(pr.drug) LIKE '%canagliflozin%' OR
             LOWER(pr.drug) LIKE '%dapagliflozin%' OR
             LOWER(pr.drug) LIKE '%empagliflozin%' OR
             LOWER(pr.drug) LIKE '%pioglitazone%' OR
             LOWER(pr.drug) LIKE '%rosiglitazone%' OR
             LOWER(pr.drug) LIKE '%repaglinide%' OR
             LOWER(pr.drug) LIKE '%nateglinide%' OR
             LOWER(pr.drug) LIKE '%acarbose%' OR
             LOWER(pr.drug) LIKE '%miglitol%' OR
             LOWER(pr.drug) LIKE '%tolbutamide%' OR
             LOWER(pr.drug) LIKE '%chlorpropamide%') -- Pre-filter to only include relevant prescriptions
),
PatientMedicationStatus AS (
    -- 3. Determine medication status for each patient (hadm_id) in early and late windows
    SELECT
        hadm_id,
        MAX(CASE WHEN medication_class = 'Insulin' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS early_insulin,
        MAX(CASE WHEN medication_class = 'Oral Agent' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS early_oral_agent,
        MAX(CASE WHEN medication_class = 'Insulin' AND starttime BETWEEN GREATEST(admittime, DATETIME_SUB(dischtime, INTERVAL 72 HOUR)) AND dischtime THEN 1 ELSE 0 END) AS late_insulin,
        MAX(CASE WHEN medication_class = 'Oral Agent' AND starttime BETWEEN GREATEST(admittime, DATETIME_SUB(dischtime, INTERVAL 72 HOUR)) AND dischtime THEN 1 ELSE 0 END) AS late_oral_agent
    FROM
        MedicationClassification
    WHERE
        medication_class IS NOT NULL -- Only consider classified DM medications
    GROUP BY
        hadm_id
),
CategorizedMedicationStatus AS (
    -- 4. Categorize medication status into types for easier transition analysis (e.g., Insulin Only, Both)
    SELECT
        hadm_id,
        CASE
            WHEN early_insulin = 1 AND early_oral_agent = 1 THEN 'Both'
            WHEN early_insulin = 1 THEN 'Insulin Only'
            WHEN early_oral_agent = 1 THEN 'Oral Agent Only'
            ELSE 'No DM Meds'
        END AS early_med_category,
        CASE
            WHEN late_insulin = 1 AND late_oral_agent = 1 THEN 'Both'
            WHEN late_insulin = 1 THEN 'Insulin Only'
            WHEN late_oral_agent = 1 THEN 'Oral Agent Only'
            ELSE 'No DM Meds'
        END AS late_med_category
    FROM
        PatientMedicationStatus
),
CohortCounts AS (
    -- Get the total number of unique admissions in the cohort for percentage calculations
    SELECT COUNT(DISTINCT hadm_id) AS total_cohort_admissions
    FROM AdmissionsCohort
)
-- 5. Calculate rates and transitions
-- Early Window Rates
SELECT
    'Early Window Rates' AS AnalysisType,
    'Insulin' AS MedicationClass,
    COUNT(DISTINCT PMS.hadm_id) AS NumberOfAdmissions,
    (COUNT(DISTINCT PMS.hadm_id) * 100.0 / CC.total_cohort_admissions) AS RatePercent
FROM
    PatientMedicationStatus AS PMS, CohortCounts AS CC
WHERE
    PMS.early_insulin = 1
GROUP BY MedicationClass, AnalysisType, CC.total_cohort_admissions

UNION ALL

SELECT
    'Early Window Rates' AS AnalysisType,
    'Oral Agents' AS MedicationClass,
    COUNT(DISTINCT PMS.hadm_id) AS NumberOfAdmissions,
    (COUNT(DISTINCT PMS.hadm_id) * 100.0 / CC.total_cohort_admissions) AS RatePercent
FROM
    PatientMedicationStatus AS PMS, CohortCounts AS CC
WHERE
    PMS.early_oral_agent = 1
GROUP BY MedicationClass, AnalysisType, CC.total_cohort_admissions

UNION ALL

-- Late Window Rates
SELECT
    'Late Window Rates' AS AnalysisType,
    'Insulin' AS MedicationClass,
    COUNT(DISTINCT PMS.hadm_id) AS NumberOfAdmissions,
    (COUNT(DISTINCT PMS.hadm_id) * 100.0 / CC.total_cohort_admissions) AS RatePercent
FROM
    PatientMedicationStatus AS PMS, CohortCounts AS CC
WHERE
    PMS.late_insulin = 1
GROUP BY MedicationClass, AnalysisType, CC.total_cohort_admissions

UNION ALL

SELECT
    'Late Window Rates' AS AnalysisType,
    'Oral Agents' AS MedicationClass,
    COUNT(DISTINCT PMS.hadm_id) AS NumberOfAdmissions,
    (COUNT(DISTINCT PMS.hadm_id) * 100.0 / CC.total_cohort_admissions) AS RatePercent
FROM
    PatientMedicationStatus AS PMS, CohortCounts AS CC
WHERE
    PMS.late_oral_agent = 1
GROUP BY MedicationClass, AnalysisType, CC.total_cohort_admissions

UNION ALL

-- Early -> Late Transitions
SELECT
    'Early-to-Late Transitions' AS AnalysisType,
    CONCAT(CMS.early_med_category, ' -> ', CMS.late_med_category) AS MedicationClass,
    COUNT(DISTINCT CMS.hadm_id) AS NumberOfAdmissions,
    (COUNT(DISTINCT CMS.hadm_id) * 100.0 / CC.total_cohort_admissions) AS RatePercent
FROM
    CategorizedMedicationStatus AS CMS, CohortCounts AS CC
GROUP BY AnalysisType, CMS.early_med_category, CMS.late_med_category, CC.total_cohort_admissions
ORDER BY AnalysisType, MedicationClass;