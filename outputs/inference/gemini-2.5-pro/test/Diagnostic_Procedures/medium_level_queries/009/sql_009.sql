WITH
-- Step 1: Identify all hospital admissions for female patients aged 44-54 with a TIA diagnosis.
tia_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND (
            -- ICD-9 codes for Transient cerebral ischemia and related syndromes
            (dx.icd_version = 9 AND dx.icd_code LIKE '435%')
            -- ICD-10 codes for Transient cerebral ischaemic attacks and related syndromes
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'G45%')
        )
),

-- Step 2: Count the number of diagnostic imaging procedures for each hospital admission.
-- Imaging is identified by ICD-9/10 procedure codes and HCPCS/CPT codes.
imaging_counts AS (
    SELECT
        hadm_id,
        SUM(num_imaging) AS total_imaging_procedures
    FROM (
        -- Count imaging procedures from ICD codes
        SELECT
            hadm_id,
            COUNT(hadm_id) AS num_imaging
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
        WHERE
            -- ICD-9 codes 87-88 are for diagnostic radiology
            (icd_version = 9 AND SUBSTR(icd_code, 1, 2) IN ('87', '88'))
            -- ICD-10-PCS codes starting with 'B' are for the imaging section
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 1) = 'B')
        GROUP BY hadm_id

        UNION ALL

        -- Count imaging procedures from HCPCS/CPT codes
        SELECT
            hadm_id,
            COUNT(hadm_id) AS num_imaging
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
        WHERE
            -- CPT codes in the 7xxxx range are for radiology
            hcpcs_cd BETWEEN '70000' AND '79999'
        GROUP BY hadm_id
    ) AS all_imaging
    GROUP BY hadm_id
),

-- Step 3: Combine the patient cohort with LOS, ICU usage, and imaging counts.
admission_details AS (
    SELECT
        tia.hadm_id,
        -- Categorize Length of Stay (LOS) in days
        CASE
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL
        END AS los_category,
        -- Flag if the admission included an ICU stay
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU Stay'
            ELSE 'No ICU Stay'
        END AS icu_usage,
        -- Get the count of imaging procedures, defaulting to 0 if none
        COALESCE(img.total_imaging_procedures, 0) AS num_imaging
    FROM tia_admissions AS tia
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON tia.hadm_id = adm.hadm_id
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
        ON tia.hadm_id = icu.hadm_id
    LEFT JOIN imaging_counts AS img
        ON tia.hadm_id = img.hadm_id
)

-- Final Step: Calculate the 25th, 50th, and 75th percentiles of imaging counts,
-- grouped by LOS category and ICU usage.
SELECT
    los_category,
    icu_usage,
    -- Use APPROX_QUANTILES to find percentiles. It returns an array of 5 values:
    -- [min, p25, p50, p75, max]. We extract the ones we need.
    APPROX_QUANTILES(num_imaging, 4)[OFFSET(1)] AS p25_imaging_procedures,
    APPROX_QUANTILES(num_imaging, 4)[OFFSET(2)] AS p50_imaging_procedures,
    APPROX_QUANTILES(num_imaging, 4)[OFFSET(3)] AS p75_imaging_procedures,
    COUNT(hadm_id) AS num_admissions
FROM admission_details
-- Filter out admissions that do not fall into our specified LOS categories
WHERE los_category IS NOT NULL
GROUP BY
    los_category,
    icu_usage
ORDER BY
    los_category,
    icu_usage;