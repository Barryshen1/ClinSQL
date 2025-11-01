WITH cohort AS (
    -- Base cohort: male patients aged 64-74 with sepsis (A41.x) but without septic shock (R65.21)
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        -- Calculate length of stay in days
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 64 AND 74
        AND adm.hadm_id IN (
            -- Sepsis admissions (A41.x)
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'A41%' AND icd_version = 10
        )
        AND adm.hadm_id NOT IN (
            -- Exclude septic shock (R65.21)
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code = 'R6521' AND icd_version = 10
        )
),

-- Assign quartiles based on LOS
cohort_with_quartile AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM cohort
),

-- Identify CKD (Chronic Kidney Disease) per admission
ckd AS (
    SELECT 
        hadm_id,
        1 AS has_ckd
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE 
        icd_version = 10
        AND (
            icd_code LIKE 'N18%'   -- CKD
            OR icd_code LIKE 'I13%' -- Hypertensive heart and CKD
            OR icd_code = 'N19'     -- Unspecified kidney failure
        )
    GROUP BY hadm_id
),

-- Identify Diabetes per admission
diabetes AS (
    SELECT 
        hadm_id,
        1 AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE 
        icd_version = 10
        AND (
            icd_code LIKE 'E10%' -- Type 1
            OR icd_code LIKE 'E11%' -- Type 2
            OR icd_code LIKE 'E13%' -- Other specified
        )
    GROUP BY hadm_id
)

-- Aggregate by quartile
SELECT 
    los_quartile,
    COUNT(*) AS n_patients,
    -- Mortality rate
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate_percent,
    -- CKD prevalence
    ROUND(SUM(COALESCE(ckd.has_ckd, 0)) / COUNT(*) * 100, 2) AS ckd_prevalence_percent,
    -- Diabetes prevalence
    ROUND(SUM(COALESCE(diab.has_diabetes, 0)) / COUNT(*) * 100, 2) AS diabetes_prevalence_percent
FROM cohort_with_quartile c
LEFT JOIN ckd 
    ON c.hadm_id = ckd.hadm_id
LEFT JOIN diabetes diab 
    ON c.hadm_id = diab.hadm_id
GROUP BY los_quartile
ORDER BY los_quartile;