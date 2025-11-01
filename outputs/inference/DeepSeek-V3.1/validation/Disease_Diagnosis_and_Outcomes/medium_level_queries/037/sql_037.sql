WITH sepsis_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.admission_type,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Check for septic shock: ICD-10 R65.21 or ICD-9 995.92
        MAX(CASE 
            WHEN diag.icd_code = 'R65.21' AND diag.icd_version = 10 THEN 1
            WHEN diag.icd_code = '995.92' AND diag.icd_version = 9 THEN 1
            ELSE 0 
        END) AS septic_shock,
        -- Count distinct ICD codes as proxy for comorbidity count
        COUNT(DISTINCT diag.icd_code) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND (
            -- Sepsis codes: ICD-10 A41.*, R65.20; ICD-9 038.*, 995.91
            (diag.icd_version = 10 AND diag.icd_code LIKE 'A41%') 
            OR (diag.icd_version = 10 AND diag.icd_code = 'R65.20')
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '038%')
            OR (diag.icd_version = 9 AND diag.icd_code = '995.91')
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.admission_type, adm.hospital_expire_flag, los_days
),
los_groups AS (
    SELECT 
        *,
        CASE 
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
            WHEN los_days >= 8 THEN '>=8'
            ELSE 'Other'
        END AS los_group
    FROM sepsis_cohort
)
SELECT 
    CASE 
        WHEN septic_shock = 1 THEN 'Septic shock'
        ELSE 'No shock'
    END AS sepsis_severity,
    los_group,
    admission_type,
    COUNT(*) AS num_patients,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
    ROUND(AVG(comorbidity_count), 2) AS mean_comorbidity_count
FROM los_groups
GROUP BY sepsis_severity, los_group, admission_type
ORDER BY sepsis_severity, los_group, admission_type;