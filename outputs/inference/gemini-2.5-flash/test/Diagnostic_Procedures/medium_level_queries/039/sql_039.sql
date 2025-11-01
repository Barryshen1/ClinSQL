WITH admissions_age_gender AS (
    -- Step 1: Select the target patient cohort (males, age 77-87 at admission)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year + pa.anchor_age AS age_at_admission,
        TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year + pa.anchor_age) BETWEEN 77 AND 87
        -- Pre-filter LOS to the relevant range to optimize subsequent joins
        AND TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 8
),
icu_and_los_categorized AS (
    -- Step 2 & 3: Determine ICU status and categorize Length of Stay (LOS)
    SELECT
        aag.subject_id,
        aag.hadm_id,
        aag.admittime,
        aag.dischtime,
        aag.los_days,
        CASE
            WHEN aag.los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN aag.los_days BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE NULL -- This should not happen due to initial LOS filter, but kept for clarity
        END AS los_group,
        CASE
            WHEN icu.stay_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS care_unit_type
    FROM
        admissions_age_gender aag
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON aag.subject_id = icu.subject_id AND aag.hadm_id = icu.hadm_id
    WHERE
        -- Ensure only admissions falling into desired LOS groups are included
        (aag.los_days BETWEEN 1 AND 4 OR aag.los_days BETWEEN 5 AND 8)
),
ct_mri_icd_codes AS (
    -- Step 4a: Identify ICD codes corresponding to CT or MRI procedures
    SELECT DISTINCT
        dicd.icd_code,
        dicd.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dicd
    WHERE
        LOWER(dicd.long_title) LIKE '%computed tomography%'
        OR LOWER(dicd.long_title) LIKE '%ct scan%'
        OR LOWER(dicd.long_title) LIKE '%computerized axial tomography%'
        OR LOWER(dicd.long_title) LIKE '%magnetic resonance imaging%'
        OR LOWER(dicd.long_title) LIKE '%mri%'
),
admission_ct_mri_counts AS (
    -- Step 4b: Count CT/MRI procedures per admission
    SELECT
        proc.hadm_id,
        COUNT(proc.icd_code) AS num_ct_mri_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    INNER JOIN
        ct_mri_icd_codes cmicd
        ON proc.icd_code = cmicd.icd_code AND proc.icd_version = cmicd.icd_version
    GROUP BY
        proc.hadm_id
)
-- Final aggregation
SELECT
    ilc.los_group,
    ilc.care_unit_type,
    COUNT(DISTINCT ilc.hadm_id) AS num_admissions,
    MIN(COALESCE(acmc.num_ct_mri_procedures, 0)) AS min_ct_mri_per_admission,
    MAX(COALESCE(acmc.num_ct_mri_procedures, 0)) AS max_ct_mri_per_admission,
    AVG(COALESCE(acmc.num_ct_mri_procedures, 0)) AS mean_ct_mri_per_admission
FROM
    icu_and_los_categorized ilc
LEFT JOIN
    admission_ct_mri_counts acmc
    ON ilc.hadm_id = acmc.hadm_id
GROUP BY
    ilc.los_group,
    ilc.care_unit_type
ORDER BY
    ilc.los_group,
    ilc.care_unit_type;