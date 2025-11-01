WITH SepsisAdmissions AS (
    -- Step 1: Identify male patients aged 48-58 and their admissions
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
        p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
),
SepsisDiagnoses AS (
    -- Step 2a: Identify admissions with sepsis ICD codes
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code = '99591')) OR -- Septicemia, Sepsis
        (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520')) -- Streptococcal sepsis, Other sepsis, Sepsis without septic shock
),
ShockDiagnoses AS (
    -- Step 2b: Identify admissions with septic shock ICD codes
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code IN ('78552', '99592')) OR -- Septic shock, Severe sepsis (often implies shock)
        (icd_version = 10 AND icd_code IN ('R6521', 'A419', 'A4150', 'A4189', 'A4190')) -- Sepsis with septic shock, Sepsis, unspecified etc.
        -- Note: Broadened shock ICD-10 slightly based on common interpretations, but original R6521 is key.
        -- For robust "no shock", it's important to exclude all relevant shock codes.
),
FilteredSepsisAdmissions AS (
    -- Step 2c: Filter for admissions with sepsis but no shock
    SELECT
        sa.subject_id,
        sa.hadm_id,
        sa.admittime,
        sa.dischtime
    FROM
        SepsisAdmissions sa
    INNER JOIN
        SepsisDiagnoses sd
        ON sa.hadm_id = sd.hadm_id
    WHERE NOT EXISTS ( -- Replaced LEFT ANTI JOIN with WHERE NOT EXISTS
        SELECT 1
        FROM ShockDiagnoses shd
        WHERE sa.hadm_id = shd.hadm_id
    )
),
UltrasoundCodes AS (
    -- Step 3a: Identify all ICD procedure codes that describe ultrasound from d_icd_procedures
    SELECT DISTINCT
        dicd.icd_code,
        dicd.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    WHERE
        LOWER(dicd.long_title) LIKE '%ultrasound%' OR -- Added LOWER to ensure case-insensitivity
        LOWER(dicd.long_title) LIKE '%echocardiography%'
        -- Considering common ultrasound-related procedures
),
UltrasoundCounts AS (
    -- Step 3b: Count the number of ultrasound procedures per admission
    SELECT
        proc.hadm_id,
        COUNT(*) AS num_ultrasounds
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN
        UltrasoundCodes uc
        ON proc.icd_code = uc.icd_code AND proc.icd_version = uc.icd_version
    GROUP BY
        proc.hadm_id
),
AdmissionDetails AS (
    -- Step 4: Calculate LOS and categorize, and determine ICU stay status for filtered admissions
    SELECT
        fsa.subject_id,
        fsa.hadm_id,
        DATE_DIFF(fsa.dischtime, fsa.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(fsa.dischtime, fsa.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN DATE_DIFF(fsa.dischtime, fsa.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE NULL -- Admissions outside 1-8 days LOS will be filtered out next
        END AS los_group,
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU Stay' -- Changed icu.stay_id to icu.hadm_id (more robust check for presence)
            ELSE 'No ICU Stay'
        END AS icu_status
    FROM
        FilteredSepsisAdmissions fsa
    LEFT JOIN (
        SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) icu -- Use DISTINCT hadm_id from icustays to avoid duplicate rows from multiple ICU stays within one admission
    ON fsa.hadm_id = icu.hadm_id
)
-- Step 5: Final aggregation to get patient counts and mean ultrasounds by strata
SELECT
    ad.icu_status,
    ad.los_group,
    COUNT(DISTINCT ad.hadm_id) AS patient_count,
    -- Calculate mean ultrasounds per admission, ensuring 0 is counted for no ultrasounds
    AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission -- Corrected AVG calculation
FROM
    AdmissionDetails ad
LEFT JOIN
    -- Join with ultrasound counts to include admissions with 0 ultrasounds
    UltrasoundCounts uc
    ON ad.hadm_id = uc.hadm_id
WHERE
    ad.los_group IS NOT NULL -- Filter to include only specified LOS groups (1-4 and 5-8 days)
GROUP BY
    ad.icu_status,
    ad.los_group
ORDER BY
    ad.icu_status,
    ad.los_group;