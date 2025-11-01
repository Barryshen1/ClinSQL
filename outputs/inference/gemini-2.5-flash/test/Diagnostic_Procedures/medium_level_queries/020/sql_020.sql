WITH AdmissionsFiltered AS (
    -- CTE 1: Filter admissions based on gender, age, TIA diagnosis, and initial LOS range
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 72 AND 82
        AND (
            (di.icd_version = 9 AND di.icd_code BETWEEN '4350' AND '4359') -- ICD-9 TIA codes (435.0-435.9)
            OR (di.icd_version = 10 AND di.icd_code LIKE 'G45%') -- ICD-10 TIA codes (G45.x)
        )
    GROUP BY -- Group by hadm_id to ensure unique admissions after filtering for TIA
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, p.anchor_age
    HAVING -- LOS filter applied here
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7
),
ICUStatus_LOSCategory AS (
    -- CTE 2: Determine ICU status and LOS category for eligible admissions
    SELECT
        af.hadm_id,
        CASE
            WHEN af.los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN af.los_days BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE 'Other' -- This 'Other' case should not be reached due to the HAVING clause in AdmissionsFiltered
        END AS los_category,
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM
        AdmissionsFiltered af
    LEFT JOIN
        (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) icu
        ON af.hadm_id = icu.hadm_id
),
ImagingProceduresCount AS (
    -- CTE 3: Count diagnostic imaging procedures for each eligible admission
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS num_imaging_procedures -- Count of procedure instances
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    WHERE
        (
            (pr.icd_version = 9 AND pr.icd_code BETWEEN '8700' AND '8939') -- ICD-9 Diagnostic Radiology, Ultrasound, MRI etc.
            OR (pr.icd_version = 10 AND STARTS_WITH(pr.icd_code, 'B')) -- ICD-10-PCS Imaging section (B section)
        )
    GROUP BY
        pr.hadm_id
)
-- Final SELECT to aggregate results
SELECT
    islc.los_category,
    islc.icu_status,
    COUNT(islc.hadm_id) AS admission_counts,
    AVG(COALESCE(ipc.num_imaging_procedures, 0)) AS mean_imaging_procedures_per_admission
FROM
    ICUStatus_LOSCategory islc
LEFT JOIN -- Use LEFT JOIN to include admissions that may have 0 imaging procedures
    ImagingProceduresCount ipc
    ON islc.hadm_id = ipc.hadm_id
GROUP BY
    islc.los_category,
    islc.icu_status
ORDER BY
    islc.los_category,
    islc.icu_status;