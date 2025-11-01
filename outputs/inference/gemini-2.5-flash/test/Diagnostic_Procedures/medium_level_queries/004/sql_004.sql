WITH AdmissionsFiltered AS (
    -- Step 1: Filter admissions based on gender, age, and LOS range
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) >= 1 AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) <= 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) >= 4 AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) <= 7 THEN '4-7 days'
            ELSE NULL -- This case should be filtered out by the outer WHERE clause 'los_days BETWEEN 1 AND 7' if only valid LOS are selected.
        END AS los_category,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 45 AND 55
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) >= 1
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) <= 7
),
HFDiagnosisCategorized AS (
    -- Step 2: Categorize each filtered admission by HF diagnosis type
    SELECT
        af.hadm_id,
        af.los_category,
        af.los_days, -- Keep los_days for potential debugging or future use, though los_category is used for grouping
        CASE
            WHEN EXISTS ( -- Check if primary diagnosis is HF
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE di.hadm_id = af.hadm_id
                    AND di.seq_num = 1 -- Primary diagnosis
                    AND (
                           (di.icd_version = 9 AND di.icd_code LIKE '428%')
                        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                    )
            ) THEN 'Primary HF'
            WHEN EXISTS ( -- Check if any secondary diagnosis is HF
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE di.hadm_id = af.hadm_id
                    AND di.seq_num > 1 -- Secondary diagnosis
                    AND (
                           (di.icd_version = 9 AND di.icd_code LIKE '428%')
                        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                    )
            )
            AND NOT EXISTS ( -- Ensure primary is NOT HF for it to be counted as 'Secondary HF'
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_primary_check
                WHERE di_primary_check.hadm_id = af.hadm_id
                    AND di_primary_check.seq_num = 1
                    AND (
                           (di_primary_check.icd_version = 9 AND di_primary_check.icd_code LIKE '428%')
                        OR (di_primary_check.icd_version = 10 AND di_primary_check.icd_code LIKE 'I50%')
                    )
            ) THEN 'Secondary HF'
            ELSE NULL -- This admission does not fit the HF criteria for either primary or secondary HF grouping
        END AS hf_diagnosis_group
    FROM
        AdmissionsFiltered af
    WHERE
        EXISTS ( -- Ensure the admission has at least one HF diagnosis (primary or secondary)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_any_hf
            WHERE di_any_hf.hadm_id = af.hadm_id
                AND (
                       (di_any_hf.icd_version = 9 AND di_any_hf.icd_code LIKE '428%')
                    OR (di_any_hf.icd_version = 10 AND di_any_hf.icd_code LIKE 'I50%')
                )
        )
),
CT_MRI_ProceduresCount AS (
    -- Step 3: Count CT/MRI procedures per admission
    SELECT
        pi.hadm_id,
        COUNT(pi.icd_code) AS num_ct_mri_per_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE
        LOWER(dip.long_title) LIKE '%computed tomograph%'
        OR LOWER(dip.long_title) LIKE '%ct scan%'
        OR LOWER(dip.long_title) LIKE '%magnetic resonance imagin%' -- truncated to catch 'imaging'
        OR LOWER(dip.long_title) LIKE '%mri%'
    GROUP BY
        pi.hadm_id
)
-- Final aggregation
SELECT
    hfc.hf_diagnosis_group,
    hfc.los_category,
    COUNT(DISTINCT hfc.hadm_id) AS num_admissions,
    AVG(COALESCE(ct.num_ct_mri_per_admission, 0)) AS mean_ct_mri_per_admission,
    MIN(COALESCE(ct.num_ct_mri_per_admission, 0)) AS min_ct_mri_per_admission,
    MAX(COALESCE(ct.num_ct_mri_per_admission, 0)) AS max_ct_mri_per_admission
FROM
    HFDiagnosisCategorized hfc
LEFT JOIN
    CT_MRI_ProceduresCount ct
    ON hfc.hadm_id = ct.hadm_id
WHERE
    hfc.hf_diagnosis_group IS NOT NULL -- Exclude admissions where HF diagnosis type could not be determined
GROUP BY
    hfc.hf_diagnosis_group,
    hfc.los_category
ORDER BY
    hfc.hf_diagnosis_group,
    hfc.los_category;