WITH cohort_admissions AS (
    -- Select female patients aged 62-72 with a lower GI bleed diagnosis
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
        -- Ensure the admission has a diagnosis of lower GI bleed
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
                ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for lower GI bleed
                    (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^578|562\.(11|13)|569\.(3|85)'))
                    OR
                    -- ICD-10 codes for lower GI bleed
                    (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^K92\.[12]|K62\.5|K57\.[0-9][02]'))
                )
        )
),
icu_status AS (
    -- Determine ICU stay status for each admission in the cohort
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.los_days,
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = ca.hadm_id)
            THEN 'With ICU Stay'
            ELSE 'Without ICU Stay'
        END AS icu_status_group
    FROM
        cohort_admissions ca
),
admission_diagnostics AS (
    -- Identify and count distinct categories of non-invasive diagnostics per admission
    SELECT
        p_icd.hadm_id,
        COUNT(DISTINCT
            CASE
                -- Imaging procedures
                WHEN p_icd.icd_version = 9 AND (LEFT(p_icd.icd_code, 2) IN ('87', '88')) THEN 'Imaging'
                WHEN p_icd.icd_version = 10 AND (
                    LEFT(p_icd.icd_code, 1) = 'B' -- Diagnostic Imaging section in ICD-10-PCS
                    OR REGEXP_CONTAINS(d_p.long_title, r'(?i)(Computed Tomography|Magnetic Resonance Imaging|Ultrasound|X-Ray|Radiography|Scan, Bone|Scan, Nuclear|Fluoroscopy)')
                ) THEN 'Imaging'
                -- ECG (Electrocardiogram)
                WHEN p_icd.icd_version = 9 AND p_icd.icd_code = '8952' THEN 'ECG'
                WHEN p_icd.icd_version = 10 AND REGEXP_CONTAINS(d_p.long_title, r'(?i)(Electrocardiogram|Cardiac Electrical Activity, Measurement)') THEN 'ECG'
                -- EEG (Electroencephalogram)
                WHEN p_icd.icd_version = 9 AND p_icd.icd_code = '8914' THEN 'EEG'
                WHEN p_icd.icd_version = 10 AND REGEXP_CONTAINS(d_p.long_title, r'(?i)Electroencephalogram') THEN 'EEG'
                -- PFT (Pulmonary Function Test)
                WHEN p_icd.icd_version = 9 AND p_icd.icd_code = '8937' THEN 'PFT'
                WHEN p_icd.icd_version = 10 AND REGEXP_CONTAINS(d_p.long_title, r'(?i)Pulmonary Function Test)') THEN 'PFT'
                ELSE NULL
            END
        ) AS num_diagnostics
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_p
        ON p_icd.icd_code = d_p.icd_code AND p_icd.icd_version = d_p.icd_version
    INNER JOIN
        cohort_admissions ca
        ON p_icd.hadm_id = ca.hadm_id
    GROUP BY
        p_icd.hadm_id
)
SELECT
    CASE
        WHEN icu.los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN icu.los_days BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE 'Other/Excluded LOS' -- Should not be in final result due to WHERE clause
    END AS los_category,
    icu.icu_status_group,
    AVG(COALESCE(ad.num_diagnostics, 0)) AS mean_number_of_non_invasive_diagnostics
FROM
    icu_status icu
LEFT JOIN
    admission_diagnostics ad
    ON icu.hadm_id = ad.hadm_id
WHERE
    icu.los_days BETWEEN 1 AND 7 -- Exclude admissions with LOS outside 1-7 days
GROUP BY
    los_category,
    icu.icu_status_group
ORDER BY
    los_category,
    icu_status_group;