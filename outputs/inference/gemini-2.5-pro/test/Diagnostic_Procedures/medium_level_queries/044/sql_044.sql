WITH 
-- Step 1: Identify all hospital admissions for the patient cohort (females, age 62-72)
-- and categorize them by length of stay (LOS).
cohort_admissions AS (
    SELECT
        a.hadm_id,
        CASE
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
        END AS los_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
        AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Step 2: Identify and count all relevant non-invasive diagnostic procedures per admission.
-- This includes imaging, ECG, EEG, and PFTs from both ICD and HCPCS codes.
diagnostic_counts AS (
    WITH diagnostic_procedures AS (
        -- Part A: Procedures from ICD codes
        SELECT
            proc.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
            ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
        WHERE
            LOWER(d_proc.long_title) LIKE '%tomography%'
            OR LOWER(d_proc.long_title) LIKE '%radiograph%'
            OR LOWER(d_proc.long_title) LIKE '%x-ray%'
            OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imaging%'
            OR LOWER(d_proc.long_title) LIKE '%ultrasound%'
            OR LOWER(d_proc.long_title) LIKE '%echocardiogra%'
            OR LOWER(d_proc.long_title) LIKE '%electrocardiogram%'
            OR LOWER(d_proc.long_title) LIKE '%ecg%'
            OR LOWER(d_proc.long_title) LIKE '%electroencephalogram%'
            OR LOWER(d_proc.long_title) LIKE '%eeg%'
            OR LOWER(d_proc.long_title) LIKE '%pulmonary function test%'

        UNION ALL

        -- Part B: Procedures from HCPCS codes (using standard code ranges)
        SELECT
            hcpcs.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
        WHERE
            -- Radiology (e.g., X-ray, CT, MRI, Ultrasound)
            (hcpcs.hcpcs_cd >= '70000' AND hcpcs.hcpcs_cd < '80000') OR
            -- Electrocardiograms (ECG)
            (hcpcs.hcpcs_cd >= '93000' AND hcpcs.hcpcs_cd < '93300') OR
            -- Pulmonary Function Tests (PFT)
            (hcpcs.hcpcs_cd >= '94000' AND hcpcs.hcpcs_cd < '94800') OR
            -- Electroencephalograms (EEG)
            (hcpcs.hcpcs_cd >= '95800' AND hcpcs.hcpcs_cd < '96000')
    )
    SELECT
        hadm_id,
        COUNT(*) AS num_diagnostics
    FROM diagnostic_procedures
    GROUP BY hadm_id
)

-- Step 3: Final aggregation to calculate the mean number of diagnostics
-- stratified by LOS group and ICU status.
SELECT
    ca.los_group,
    CASE 
        WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
        ELSE 'No ICU'
    END AS icu_status,
    AVG(COALESCE(dc.num_diagnostics, 0)) AS mean_diagnostics_per_admission
FROM
    cohort_admissions AS ca
LEFT JOIN
    -- Identify admissions that had at least one ICU stay
    (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
    ON ca.hadm_id = icu.hadm_id
LEFT JOIN
    diagnostic_counts AS dc
    ON ca.hadm_id = dc.hadm_id
GROUP BY
    los_group,
    icu_status
ORDER BY
    los_group,
    icu_status;