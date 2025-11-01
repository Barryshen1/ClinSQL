WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        a.hospital_expire_flag,
        -- Check if ICU stay exists
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
        -- LOS: for ICU patients use icustays.los, for non-ICU compute from admissions
        CASE 
            WHEN i.stay_id IS NOT NULL THEN i.los 
            ELSE DATETIME_DIFF(a.dischtime, a.admittime, DAY) 
        END AS los_days,
        -- Check for CKD (ICD-10 N18.*)
        MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
        -- Check for Diabetes (ICD-10 E10.*, E11.*, E13.*)
        MAX(CASE WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
        ON a.hadm_id = hf.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    -- Check for comorbidities (CKD and Diabetes) in the same admission
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 80 AND 90
        AND hf.icd_code LIKE 'I50%'  -- Heart failure ICD-10 codes
    GROUP BY p.subject_id, a.hadm_id, p.anchor_age, a.hospital_expire_flag, i.stay_id, i.los, a.admittime, a.dischtime
),
stratified AS (
    SELECT 
        subject_id,
        hadm_id,
        anchor_age,
        hospital_expire_flag,
        icu_status,
        -- Categorize LOS
        CASE 
            WHEN los_days < 8 THEN '<8'
            ELSE '>=8'
        END AS los_group,
        has_ckd,
        has_diabetes
    FROM cohort
)
SELECT 
    icu_status,
    los_group,
    COUNT(*) AS n_patients,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
    ROUND(100 * AVG(has_ckd), 2) AS ckd_percent,
    ROUND(100 * AVG(has_diabetes), 2) AS diabetes_percent
FROM stratified
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;