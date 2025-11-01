WITH hf_patients AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
            ELSE 'Other'
        END AS los_category,
        CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
        ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 38 AND 48
        AND (ddx.icd_code LIKE 'I50%' OR ddx.icd_code LIKE '428%')
),
-- Placeholder for Charlson computation: we would need to add comorbidity count here.
-- For now, we set it to NULL.
cohort AS (
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los_category,
        icu_status,
        NULL AS charlson_count  -- Replace with actual computed value
    FROM hf_patients
),
stratified AS (
    SELECT
        icu_status,
        los_category,
        COUNT(*) AS n,
        SUM(hospital_expire_flag) AS deaths,
        AVG(hospital_expire_flag) * 100 AS mortality_percent,
        -- 95% CI using normal approximation
        AVG(hospital_expire_flag) * 100 - 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*)) * 100 AS ci_lower,
        AVG(hospital_expire_flag) * 100 + 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*)) * 100 AS ci_upper,
        AVG(charlson_count) AS mean_comorbidity_count
    FROM cohort
    GROUP BY icu_status, los_category
)
SELECT
    icu_status,
    los_category,
    n,
    deaths,
    mortality_percent,
    ci_lower,
    ci_upper,
    mean_comorbidity_count
FROM stratified
ORDER BY icu_status, los_category;