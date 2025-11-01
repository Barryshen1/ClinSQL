WITH hf_admissions AS (
    -- Step 1: Identify all hospital admissions (hadm_id) for the cohort of interest.
    -- Cohort: Females, 80-90 years old, with a diagnosis of Heart Failure.
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 80 AND 90
        -- Filter for Heart Failure using common ICD-9 and ICD-10 codes
        AND (dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%')
),

admission_details AS (
    -- Step 2: For each admission in our cohort, gather key details:
    -- LOS, mortality, ICU stay status, and comorbidity flags for CKD and Diabetes.
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
        -- Flag if there was any ICU stay during this hospital admission
        MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_stay_flag,
        -- Flag if a CKD diagnosis is present for this admission
        MAX(CASE
            WHEN dx.icd_code LIKE '585%' OR dx.icd_code LIKE 'N18%' THEN 1
            ELSE 0
        END) AS ckd_flag,
        -- Flag if a Diabetes diagnosis is present for this admission
        MAX(CASE
            WHEN dx.icd_code LIKE '250%' OR dx.icd_code LIKE 'E08%' OR dx.icd_code LIKE 'E09%' OR dx.icd_code LIKE 'E10%' OR dx.icd_code LIKE 'E11%' OR dx.icd_code LIKE 'E13%' THEN 1
            ELSE 0
        END) AS diabetes_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Use LEFT JOINs to check for the presence of ICU stays or specific diagnoses
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    -- Process only the admissions identified in our initial cohort
    WHERE adm.hadm_id IN (SELECT hadm_id FROM hf_admissions)
    GROUP BY
        adm.hadm_id,
        adm.hospital_expire_flag,
        hospital_los_days
)

-- Step 3: Stratify the cohort and calculate the final metrics.
SELECT
    -- Stratification columns
    CASE WHEN ad.icu_stay_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS patient_group,
    CASE WHEN ad.hospital_los_days < 8 THEN '< 8 days' ELSE '>= 8 days' END AS los_group,
    -- Final metrics
    COUNT(ad.hadm_id) AS number_of_admissions,
    -- Mortality rate: AVG of a 0/1 flag gives the proportion. Multiply by 100 for percentage.
    ROUND(AVG(ad.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
    -- CKD prevalence: AVG of the 0/1 flag.
    ROUND(AVG(ad.ckd_flag) * 100, 2) AS ckd_prevalence_pct,
    -- Diabetes prevalence: AVG of the 0/1 flag.
    ROUND(AVG(ad.diabetes_flag) * 100, 2) AS diabetes_prevalence_pct
FROM admission_details AS ad
-- Exclude admissions where LOS could not be calculated (e.g., ongoing admissions)
WHERE ad.hospital_los_days IS NOT NULL
GROUP BY
    patient_group,
    los_group
ORDER BY
    patient_group DESC,
    los_group;