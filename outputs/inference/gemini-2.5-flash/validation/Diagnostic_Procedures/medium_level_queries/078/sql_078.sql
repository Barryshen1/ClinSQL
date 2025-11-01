WITH AdmissionsFiltered AS (
    -- Select relevant admissions based on demographics and TIA diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 88 AND 98
        -- Check for TIA diagnosis (ICD-9: 435.x, ICD-10: G45.x)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 9 AND di.icd_code LIKE '435%') OR
                    (di.icd_version = 10 AND di.icd_code LIKE 'G45%')
                )
        )
),
AdmissionsWithLOSCategory AS (
    -- Categorize admissions by Length of Stay
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los_days,
        CASE
            WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
            WHEN los_days >= 4 AND los_days <= 7 THEN '4-7 days'
            ELSE 'Other' -- Exclude admissions outside this range later
        END AS los_category
    FROM
        AdmissionsFiltered
    WHERE
        los_days >= 1 AND los_days <= 7 -- Only consider 1-7 day stays for the categories
),
AdmissionsWithICU AS (
    -- Determine if the admission involved an ICU stay
    SELECT
        af.subject_id,
        af.hadm_id,
        af.los_category,
        CASE WHEN icu.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
    FROM
        AdmissionsWithLOSCategory af
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON af.subject_id = icu.subject_id AND af.hadm_id = icu.hadm_id
),
CT_MRI_Procedures AS (
    -- Identify ICD procedure codes corresponding to CT/MRI studies
    SELECT
        proc.subject_id,
        proc.hadm_id,
        proc.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        LOWER(d_proc.long_title) LIKE '%computed tomography%'
        OR LOWER(d_proc.long_title) LIKE '%ct scan%'
        OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imaging%'
),
AdmissionStudyCounts AS (
    -- Count the number of CT/MRI studies for each relevant admission
    SELECT
        ai.subject_id,
        ai.hadm_id,
        ai.los_category,
        ai.icu_use,
        COUNT(ctmri.icd_code) AS num_ct_mri_studies -- Count occurrences of CT/MRI procedures
    FROM
        AdmissionsWithICU ai
    LEFT JOIN
        CT_MRI_Procedures ctmri
        ON ai.subject_id = ctmri.subject_id AND ai.hadm_id = ctmri.hadm_id
    GROUP BY
        ai.subject_id,
        ai.hadm_id,
        ai.los_category,
        ai.icu_use
)
-- Final aggregation to calculate median and IQR for each stratum
SELECT
    los_category,
    icu_use,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    APPROX_QUANTILES(num_ct_mri_studies, 100)[OFFSET(50)] AS median_studies, -- Median (50th percentile)
    APPROX_QUANTILES(num_ct_mri_studies, 100)[OFFSET(25)] AS q1_studies,    -- 25th percentile
    APPROX_QUANTILES(num_ct_mri_studies, 100)[OFFSET(75)] AS q3_studies     -- 75th percentile
FROM
    AdmissionStudyCounts
WHERE
    los_category IN ('1-3 days', '4-7 days') -- Ensure only specified LOS categories are included
GROUP BY
    los_category,
    icu_use
ORDER BY
    los_category,
    icu_use;