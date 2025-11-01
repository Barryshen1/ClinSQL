WITH base_admissions AS (
    -- Select base demographic and admission information, filter by age and gender
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        pa.gender,
        pa.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 80 AND 90
),
hadm_hf AS (
    -- Identify admissions with a Heart Failure diagnosis using ICD codes
    SELECT DISTINCT
        diagnoses.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
    WHERE
        (diagnoses.icd_version = 9 AND diagnoses.icd_code LIKE '428%') -- ICD-9 for Heart Failure
        OR (diagnoses.icd_version = 10 AND diagnoses.icd_code LIKE 'I50%') -- ICD-10 for Heart Failure
),
hadm_ckd AS (
    -- Identify admissions with a Chronic Kidney Disease (CKD) diagnosis using ICD codes
    SELECT DISTINCT
        diagnoses.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
    WHERE
        (diagnoses.icd_version = 9 AND diagnoses.icd_code LIKE '585%') -- ICD-9 for CKD
        OR (diagnoses.icd_version = 10 AND diagnoses.icd_code LIKE 'N18%') -- ICD-10 for CKD
),
hadm_dm AS (
    -- Identify admissions with a Diabetes Mellitus (DM) diagnosis using ICD codes
    SELECT DISTINCT
        diagnoses.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
    WHERE
        (diagnoses.icd_version = 9 AND diagnoses.icd_code LIKE '250%') -- ICD-9 for Diabetes
        OR (diagnoses.icd_version = 10 AND (diagnoses.icd_code LIKE 'E10%' OR diagnoses.icd_code LIKE 'E11%' OR diagnoses.icd_code LIKE 'E12%' OR diagnoses.icd_code LIKE 'E13%')) -- ICD-10 for Diabetes
),
icu_admissions AS (
    -- Identify admissions that included at least one ICU stay
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),
final_cohort AS (
    -- Combine all information and create flags for stratification and outcomes
    SELECT
        b.subject_id,
        b.hadm_id,
        b.hospital_expire_flag,
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status,
        CASE
            WHEN b.los_days < 8 THEN 'LOS < 8 Days'
            ELSE 'LOS >= 8 Days'
        END AS los_group,
        -- Binary flags for presence of conditions
        CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
        CASE WHEN dm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes
    FROM
        base_admissions AS b
    INNER JOIN
        hadm_hf AS hf -- Filter to only include admissions with Heart Failure
        ON b.hadm_id = hf.hadm_id
    LEFT JOIN
        icu_admissions AS icu
        ON b.hadm_id = icu.hadm_id
    LEFT JOIN
        hadm_ckd AS ckd
        ON b.hadm_id = ckd.hadm_id
    LEFT JOIN
        hadm_dm AS dm
        ON b.hadm_id = dm.hadm_id
)
-- Final aggregation to calculate requested metrics
SELECT
    icu_status,
    los_group,
    COUNT(DISTINCT subject_id) AS num_patients,
    COUNT(hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100 AS in_hospital_mortality_percent,
    SAFE_DIVIDE(SUM(has_ckd), COUNT(hadm_id)) * 100 AS ckd_prevalence_percent,
    SAFE_DIVIDE(SUM(has_diabetes), COUNT(hadm_id)) * 100 AS diabetes_prevalence_percent
FROM
    final_cohort
GROUP BY
    icu_status,
    los_group
ORDER BY
    icu_status,
    los_group;