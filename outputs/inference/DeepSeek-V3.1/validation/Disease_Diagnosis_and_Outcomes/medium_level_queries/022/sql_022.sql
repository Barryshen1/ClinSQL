WITH sepsis_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Check if had any ICU stay within first day
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
            WHERE adm.hadm_id = icu.hadm_id 
            AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
        ) THEN 'Yes' ELSE 'No' END AS day1_icu
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                -- ICD-10 codes for sepsis without shock
                (icd_version = 10 AND icd_code LIKE 'A41%') 
                OR (icd_version = 10 AND icd_code = 'R65.20')
                -- ICD-9 codes for sepsis without shock
                OR (icd_version = 9 AND icd_code LIKE '038%')
                OR (icd_version = 9 AND icd_code = '995.52')
        )
        -- Exclude septic shock codes
        AND adm.hadm_id NOT IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                (icd_version = 10 AND icd_code = 'R65.21') 
                OR (icd_version = 9 AND icd_code = '785.52')
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
)
SELECT 
    CASE WHEN los_days <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END AS los_group,
    day1_icu,
    COUNT(*) AS num_patients,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    APPROX_QUANTILE(los_days, 0.5) AS median_los_days
FROM sepsis_cohort
GROUP BY 
    CASE WHEN los_days <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END,
    day1_icu
ORDER BY los_group, day1_icu;