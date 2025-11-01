WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Compute age at admission: anchor_age + (year of admission - anchor_year)
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND adm.hadm_id IN (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE 
                (icd_code LIKE 'A41%' OR icd_code = 'R65.20')
                AND icd_version = 10
                AND hadm_id NOT IN (
                    SELECT hadm_id
                    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
                    WHERE icd_code = 'R65.21' AND icd_version = 10
                )
        )
),
-- Filter cohort to age 75-85
cohort_filtered AS (
    SELECT *
    FROM cohort
    WHERE age_at_admit BETWEEN 75 AND 85
),
-- Comorbidity flags for each hadm_id
comorbidities AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN icd_code LIKE 'N18%' AND icd_version = 10 THEN 1 ELSE 0 END) AS ckd,
        MAX(CASE WHEN (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%') AND icd_version = 10 THEN 1 ELSE 0 END) AS diabetes,
        MAX(CASE WHEN icd_code LIKE 'I48%' AND icd_version = 10 THEN 1 ELSE 0 END) AS afib,
        MAX(CASE WHEN icd_code = 'I10' AND icd_version = 10 THEN 1 ELSE 0 END) AS hypertension
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
-- Combine cohort with comorbidities
cohort_comorb AS (
    SELECT 
        c.*,
        COALESCE(com.ckd, 0) AS ckd,
        COALESCE(com.diabetes, 0) AS diabetes,
        COALESCE(com.afib, 0) AS afib,
        COALESCE(com.hypertension, 0) AS hypertension
    FROM cohort_filtered c
    LEFT JOIN comorbidities com
        ON c.hadm_id = com.hadm_id
),
-- Group LOS
cohort_los AS (
    SELECT *,
        CASE WHEN los <= 5 THEN '<=5' ELSE '>5' END AS los_group
    FROM cohort_comorb
)
-- Calculate mortality for each LOS group and each comorbidity
SELECT 
    los_group,
    'CKD' AS comorbidity,
    ckd AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM cohort_los
GROUP BY los_group, ckd
UNION ALL
SELECT 
    los_group,
    'Diabetes' AS comorbidity,
    diabetes AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM cohort_los
GROUP BY los_group, diabetes
UNION ALL
SELECT 
    los_group,
    'AFib' AS comorbidity,
    afib AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM cohort_los
GROUP BY los_group, afib
UNION ALL
SELECT 
    los_group,
    'Hypertension' AS comorbidity,
    hypertension AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM cohort_los
GROUP BY los_group, hypertension
ORDER BY comorbidity, los_group, has_comorbidity;