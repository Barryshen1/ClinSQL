WITH heart_failure_admissions AS (
    -- Select admissions for women aged 83-93 with a heart failure diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Determine if the admission included an ICU stay
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = ad.hadm_id) THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_stay_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 83 AND 93
        -- Filter for Heart Failure diagnosis (ICD-9: 428%, ICD-10: I50%)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.hadm_id = ad.hadm_id
            AND (
                (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
                (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
            )
        )
),
comorbidity_flags AS (
    -- Flag common comorbidities for each admission
    -- Selected comorbidities for burden calculation: CKD, Diabetes, Hypertension, COPD, Ischemic Heart Disease
    SELECT
        hadm_id,
        -- Chronic Kidney Disease (CKD)
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '585%') OR (icd_version = 10 AND icd_code LIKE 'N18%') THEN 1 ELSE 0 END) AS has_ckd,
        -- Diabetes Mellitus
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '250%') OR (icd_version = 10 AND icd_code LIKE 'E10%') OR (icd_version = 10 AND icd_code LIKE 'E11%') OR (icd_version = 10 AND icd_code LIKE 'E12%') OR (icd_version = 10 AND icd_code LIKE 'E13%') OR (icd_version = 10 AND icd_code LIKE 'E14%') THEN 1 ELSE 0 END) AS has_diabetes,
        -- Hypertension
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '401%') OR (icd_version = 9 AND icd_code LIKE '402%') OR (icd_version = 9 AND icd_code LIKE '403%') OR (icd_version = 9 AND icd_code LIKE '404%') OR (icd_version = 9 AND icd_code LIKE '405%') OR (icd_version = 10 AND icd_code LIKE 'I10%') OR (icd_version = 10 AND icd_code LIKE 'I11%') OR (icd_version = 10 AND icd_code LIKE 'I12%') OR (icd_version = 10 AND icd_code LIKE 'I13%') OR (icd_version = 10 AND icd_code LIKE 'I15%') THEN 1 ELSE 0 END) AS has_hypertension,
        -- Chronic Obstructive Pulmonary Disease (COPD)
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '491%') OR (icd_version = 9 AND icd_code LIKE '492%') OR (icd_version = 9 AND icd_code LIKE '496%') OR (icd_version = 10 AND icd_code LIKE 'J44%') THEN 1 ELSE 0 END) AS has_copd,
        -- Ischemic Heart Disease (IHD)
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '410%') OR (icd_version = 9 AND icd_code LIKE '411%') OR (icd_version = 9 AND icd_code LIKE '412%') OR (icd_version = 9 AND icd_code LIKE '413%') OR (icd_version = 9 AND icd_code LIKE '414%') OR (icd_version = 10 AND icd_code LIKE 'I20%') OR (icd_version = 10 AND icd_code LIKE 'I21%') OR (icd_version = 10 AND icd_code LIKE 'I22%') OR (icd_version = 10 AND icd_code LIKE 'I23%') OR (icd_version = 10 AND icd_code LIKE 'I24%') OR (icd_version = 10 AND icd_code LIKE 'I25%') THEN 1 ELSE 0 END) AS has_ihd
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
        hadm_id
),
combined_data AS (
    -- Combine heart failure admissions with comorbidity flags and create stratification groups
    SELECT
        hfa.hadm_id,
        hfa.hospital_expire_flag,
        hfa.los_days,
        hfa.icu_stay_group,
        CASE
            WHEN hfa.los_days < 8 THEN '< 8 days'
            ELSE '>= 8 days'
        END AS los_group,
        -- Calculate comorbidity count, using COALESCE to handle cases where an admission might not have any of the specific comorbidities recorded in diagnoses_icd (i.e. LEFT JOIN results in NULLs)
        (COALESCE(cf.has_ckd, 0) + COALESCE(cf.has_diabetes, 0) + COALESCE(cf.has_hypertension, 0) + COALESCE(cf.has_copd, 0) + COALESCE(cf.has_ihd, 0)) AS comorbidity_count,
        COALESCE(cf.has_ckd, 0) AS has_ckd,
        COALESCE(cf.has_diabetes, 0) AS has_diabetes
    FROM
        heart_failure_admissions hfa
    LEFT JOIN
        comorbidity_flags cf
        ON hfa.hadm_id = cf.hadm_id
)
-- Final aggregation to report the requested metrics
SELECT
    cd.icu_stay_group,
    cd.los_group,
    CASE
        WHEN cd.comorbidity_count <= 1 THEN '0-1'
        WHEN cd.comorbidity_count = 2 THEN '2'
        ELSE '>=3'
    END AS comorbidity_burden_group,
    COUNT(DISTINCT cd.hadm_id) AS total_admissions,
    -- Mortality percentage
    SAFE_DIVIDE(SUM(cd.hospital_expire_flag), COUNT(DISTINCT cd.hadm_id)) * 100 AS mortality_percent,
    -- Median Length of Stay
    APPROX_QUANTILES(cd.los_days, 2)[OFFSET(1)] AS median_los_days, -- BigQuery's APPROX_QUANTILES for median
    -- CKD prevalence percentage
    SAFE_DIVIDE(SUM(cd.has_ckd), COUNT(DISTINCT cd.hadm_id)) * 100 AS ckd_prevalence_percent,
    -- Diabetes prevalence percentage
    SAFE_DIVIDE(SUM(cd.has_diabetes), COUNT(DISTINCT cd.hadm_id)) * 100 AS diabetes_prevalence_percent
FROM
    combined_data cd
GROUP BY
    cd.icu_stay_group,
    cd.los_group,
    comorbidity_burden_group
ORDER BY
    cd.icu_stay_group DESC, -- 'ICU' first, then 'Non-ICU'
    cd.los_group,
    comorbidity_burden_group;