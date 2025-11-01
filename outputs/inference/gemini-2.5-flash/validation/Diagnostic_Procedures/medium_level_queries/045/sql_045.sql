WITH DVT_PATIENTS AS (
    -- Select patients within the specified age range and gender,
    -- and filter their admissions for a DVT diagnosis.
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        p.gender,
        p.anchor_age,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 78 AND 88
        AND (
            -- ICD-9 codes for DVT (e.g., 453.4x for lower extremity DVT, 453.8x for other specific veins)
            (di.icd_version = 9 AND (di.icd_code LIKE '453.4%' OR di.icd_code LIKE '453.8%'))
            -- ICD-10 codes for DVT (I82.x - Other venous embolism and thrombosis)
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I82.%')
        )
),
ADMISSION_DETAILS AS (
    -- Calculate hospital Length of Stay (LOS) and determine ICU status for each relevant admission.
    SELECT
        dp.subject_id,
        dp.hadm_id,
        dp.admittime,
        dp.dischtime,
        DATETIME_DIFF(dp.dischtime, dp.admittime, DAY) AS hospital_los_days,
        -- Determine if the admission included an ICU stay
        CASE WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = dp.hadm_id) THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
    FROM DVT_PATIENTS dp
),
NONINVASIVE_DIAGNOSTICS_PER_ADMISSION AS (
    -- Count the number of noninvasive diagnostic procedures for each admission.
    -- Noninvasive diagnostics are broadly defined as diagnostic imaging procedures.
    SELECT
        ad.hadm_id,
        COUNT(proc.icd_code) AS num_noninvasive_diagnostics -- Count occurrences of diagnostic procedures
    FROM ADMISSION_DETAILS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON ad.hadm_id = proc.hadm_id
    WHERE
        (
            -- ICD-9 codes for Diagnostic Radiology (87.x) and Other Diagnostic Imaging (88.x, e.g., ultrasound, CT, MRI)
            proc.icd_version = 9 AND (proc.icd_code LIKE '87.%' OR proc.icd_code LIKE '88.%')
        )
        OR
        (
            -- ICD-10-PCS codes in the 'B' chapter (Imaging)
            proc.icd_version = 10 AND SUBSTR(proc.icd_code, 1, 1) = 'B'
        )
    GROUP BY
        ad.hadm_id
)
-- Final aggregation to get counts and mean by LOS group and ICU status.
SELECT
    ad.icu_status,
    -- Stratify LOS into 1-4 days and 5-8 days
    CASE
        WHEN ad.hospital_los_days >= 1 AND ad.hospital_los_days <= 4 THEN '1-4 days'
        WHEN ad.hospital_los_days >= 5 AND ad.hospital_los_days <= 8 THEN '5-8 days'
        ELSE 'Other LOS' -- Should be filtered out by the WHERE clause
    END AS los_group,
    COUNT(DISTINCT ad.hadm_id) AS num_admissions,
    SUM(COALESCE(ndi.num_noninvasive_diagnostics, 0)) AS total_noninvasive_diagnostics,
    AVG(COALESCE(ndi.num_noninvasive_diagnostics, 0)) AS mean_noninvasive_diagnostics_per_admission
FROM ADMISSION_DETAILS ad
LEFT JOIN NONINVASIVE_DIAGNOSTICS_PER_ADMISSION ndi
    ON ad.hadm_id = ndi.hadm_id
WHERE
    (ad.hospital_los_days >= 1 AND ad.hospital_los_days <= 4) -- Include only admissions with LOS 1-4 days
    OR (ad.hospital_los_days >= 5 AND ad.hospital_los_days <= 8) -- Include only admissions with LOS 5-8 days
GROUP BY
    ad.icu_status,
    los_group
ORDER BY
    ad.icu_status,
    los_group;