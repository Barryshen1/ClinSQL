WITH TroponinItemIDs AS (
    -- Step 1: Identify all itemids for serum troponin measurements
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        lower(label) LIKE '%troponin%'
        AND lower(fluid) = 'serum'
),
ACSDiagnoses AS (
    -- Step 2: Identify all hospital admissions with an Acute Coronary Syndrome (ACS) diagnosis
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND (
            icd_code LIKE 'I21%' OR  -- Acute myocardial infarction (e.g., STEMI, NSTEMI)
            icd_code = 'I200' OR     -- Unstable angina (ICD-10: I20.0)
            icd_code LIKE 'I24%'     -- Other acute ischemic heart disease
        ))
        OR
        (icd_version = 9 AND (
            icd_code LIKE '410%' OR  -- Acute myocardial infarction
            icd_code = '4111'        -- Unstable angina (ICD-9: 411.1)
        ))
),
EligiblePatientsMinTroponin AS (
    -- Step 3: Find the minimum serum troponin for each eligible patient's admission
    --         Filter by gender, age, and ACS diagnosis, then join with lab events
    SELECT
        p.subject_id,
        adm.hadm_id,
        MIN(le.valuenum) AS min_troponin_for_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN ACSDiagnoses acs_diag
        ON adm.subject_id = acs_diag.subject_id AND adm.hadm_id = acs_diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
    JOIN TroponinItemIDs ti
        ON le.itemid = ti.itemid
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 57 -- Filter for 57-year-old males
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum >= 0 -- Troponin values should be non-negative
    GROUP BY
        p.subject_id, adm.hadm_id
)
-- Step 4: Get the overall minimum troponin value from all eligible admissions
SELECT
    MIN(min_troponin_for_admission) AS overall_min_serum_troponin_in_cohort
FROM EligiblePatientsMinTroponin;