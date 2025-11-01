WITH
-- Step 1: Identify female patients in the specified age range
patient_cohort AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
        gender = 'F'
        AND anchor_age BETWEEN 83 AND 93
),

-- Step 2: Identify hospital admissions for the patient cohort with a heart failure diagnosis
hf_admissions AS (
    SELECT DISTINCT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    INNER JOIN patient_cohort AS pc
        ON di.subject_id = pc.subject_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
),

-- Step 3: Identify comorbidities for each hospital admission to calculate burden
comorbidities AS (
    SELECT
        hadm_id,
        -- Flag for Chronic Kidney Disease (CKD)
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '585%') OR (icd_version = 10 AND icd_code LIKE 'N18%') THEN 1 ELSE 0 END) AS ckd_flag,
        -- Flag for Diabetes
        MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '250%') OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) THEN 1 ELSE 0 END) AS diabetes_flag,
        -- Flag for Chronic Obstructive Pulmonary Disease (COPD)
        MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '496%')) OR (icd_version = 10 AND (icd_code LIKE 'J43%' OR icd_code LIKE 'J44%')) THEN 1 ELSE 0 END) AS copd_flag,
        -- Flag for Atrial Fibrillation (AFib)
        MAX(CASE WHEN (icd_version = 9 AND (icd_code = '427.31' OR icd_code = '427.32')) OR (icd_version = 10 AND icd_code LIKE 'I48%') THEN 1 ELSE 0 END) AS afib_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM hf_admissions)
    GROUP BY hadm_id
),

-- Step 4: Consolidate all information for each admission and create stratification groups
admission_details AS (
    SELECT
        hfa.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los,
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
        com.ckd_flag,
        com.diabetes_flag,
        (com.ckd_flag + com.diabetes_flag + com.copd_flag + com.afib_flag) AS comorbidity_count
    FROM hf_admissions AS hfa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON hfa.hadm_id = adm.hadm_id
    INNER JOIN comorbidities AS com
        ON hfa.hadm_id = com.hadm_id
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
        ON hfa.hadm_id = icu.hadm_id
    WHERE
        adm.admittime IS NOT NULL AND adm.dischtime IS NOT NULL
),

-- Step 5: Finalize stratification categories from the detailed data
stratified_admissions AS (
    SELECT
        *,
        CASE WHEN hospital_los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
        CASE
            WHEN comorbidity_count <= 1 THEN '0-1'
            WHEN comorbidity_count = 2 THEN '2'
            ELSE '3+'
        END AS comorbidity_burden
    FROM admission_details
    WHERE hospital_los >= 0 -- Exclude data errors resulting in negative LOS
)

-- Final step: Group by the strata and calculate the requested metrics
SELECT
    icu_status,
    los_group,
    comorbidity_burden,
    COUNT(*) AS number_of_admissions,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_pct,
    APPROX_QUANTILES(hospital_los, 100)[OFFSET(50)] AS median_los_days,
    ROUND(100 * AVG(ckd_flag), 2) AS ckd_prevalence_pct,
    ROUND(100 * AVG(diabetes_flag), 2) AS diabetes_prevalence_pct
FROM stratified_admissions
GROUP BY
    icu_status,
    los_group,
    comorbidity_burden
ORDER BY
    icu_status ASC, -- 'ICU' then 'Non-ICU'
    los_group ASC,
    comorbidity_burden ASC;