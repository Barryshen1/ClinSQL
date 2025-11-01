WITH cohort_admissions AS (
    -- Step 1: Identify all hospital admissions for 74-year-old female patients with heart failure.
    SELECT
        pa.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        ad.admission_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age = 74
        AND di.icd_version = 10 -- Assuming ICD-10 for heart failure diagnosis in MIMIC-IV v2.0+
        AND di.icd_code LIKE 'I50%' -- ICD-10 codes for Heart Failure (I50.xx)
    GROUP BY
        pa.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.admission_type
    HAVING
        COUNT(DISTINCT di.icd_code) >= 1 -- Ensure at least one distinct heart failure diagnosis for the admission
),
non_invasive_diagnostics_per_admission AS (
    -- Step 2: Count distinct non-invasive diagnostic procedures (imaging, ECG/EEG/PFT) per admission.
    -- Using ICD-10-PCS codes for classification.
    SELECT
        p.hadm_id,
        COUNT(DISTINCT p.icd_code) AS num_diagnostics -- Count distinct types of procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    WHERE
        p.icd_version = 10 -- Ensure using ICD-10-PCS for procedures in MIMIC-IV v2.0+
        AND (
            -- Imaging procedures (ICD-10-PCS chapter B)
            SUBSTR(p.icd_code, 1, 1) = 'B'
            -- OR Measurement of Physiological and Biological Systems (ICD-10-PCS chapter 4A)
            -- This chapter includes ECG (4A1), EEG (4A5), and many PFTs (e.g., within 4A0 or 4A7 for respiratory measurements).
            OR SUBSTR(p.icd_code, 1, 2) = '4A'
        )
    GROUP BY
        p.hadm_id
)
-- Step 3 & 4: Join the cohort admissions with procedure counts, stratify by LOS and admission type, then aggregate.
SELECT
    CASE
        WHEN ca.los_days >= 1 AND ca.los_days <= 4 THEN '1-4 days'
        WHEN ca.los_days >= 5 AND ca.los_days <= 7 THEN '5-7 days'
        -- Any other LOS will be filtered out by the WHERE clause
    END AS los_group,
    CASE
        WHEN ca.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
        WHEN ca.admission_type = 'ELECTIVE' THEN 'Elective'
        -- Any other admission types will be filtered out by the WHERE clause
    END AS admission_type_group,
    AVG(COALESCE(nida.num_diagnostics, 0)) AS mean_non_invasive_diagnostics_per_admission
FROM
    cohort_admissions ca
LEFT JOIN
    non_invasive_diagnostics_per_admission nida
    ON ca.hadm_id = nida.hadm_id
WHERE
    (ca.los_days >= 1 AND ca.los_days <= 7) -- Filter for specified LOS ranges (1-4 days and 5-7 days)
    AND ca.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE') -- Filter for specified admission types
GROUP BY
    los_group,
    admission_type_group
ORDER BY
    los_group,
    admission_type_group;