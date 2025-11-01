WITH
-- Compute birthdate from anchor_year and anchor_age
patients_with_birthdate AS (
    SELECT 
        subject_id,
        anchor_year,
        anchor_age,
        DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birthdate
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
-- Admissions with age at admission, filtered by gender and non-null discharge time
admissions_with_age AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        FLOOR(DATEDIFF(a.admittime, p.birthdate) / 365.25) AS age_at_admission,
        a.gender,
        DATEDIFF(a.dischtime, a.admittime) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN patients_with_birthdate p ON a.subject_id = p.subject_id
    WHERE 
        a.gender = 'M'
        AND a.dischtime IS NOT NULL
),
-- ACS ICD codes (expanded list for completeness)
acs_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
        long_title LIKE '%Acute Coronary Syndrome%' OR
        icd_code LIKE 'I20%' OR
        icd_code LIKE 'I21%' OR
        icd_code LIKE 'I22%' OR
        icd_code LIKE 'I23%' OR
        icd_code LIKE 'I24%' OR
        icd_code LIKE 'I25%'
),
-- Minimum seq_num for ACS per admission
admissions_with_acs AS (
    SELECT 
        hadm_id,
        MIN(seq_num) AS min_acs_seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM acs_codes)
    GROUP BY hadm_id
),
-- Primary/secondary diagnosis flag for ACS
acs_diagnosis_type AS (
    SELECT 
        hadm_id,
        CASE 
            WHEN min_acs_seq_num = 1 THEN 'primary'
            WHEN min_acs_seq_num > 1 THEN 'secondary'
            ELSE NULL 
        END AS acs_diagnosis_type
    FROM admissions_with_acs
),
-- Ultrasound HCPCS codes (sample; expand with full list in practice)
ultrasound_codes AS (
    SELECT '76600' AS code UNION ALL
    SELECT '76605' UNION ALL
    SELECT '76610' UNION ALL
    SELECT '76615' UNION ALL
    SELECT '76620' UNION ALL
    SELECT '76625' UNION ALL
    SELECT '76630' UNION ALL
    SELECT '76635' UNION ALL
    SELECT '76640' UNION ALL
    SELECT '76645' UNION ALL
    SELECT '76650' UNION ALL
    SELECT '76655' UNION ALL
    SELECT '76660' UNION ALL
    SELECT '76665' UNION ALL
    SELECT '76670' UNION ALL
    SELECT '76675' UNION ALL
    SELECT '76680' UNION ALL
    SELECT '76685' UNION ALL
    SELECT '76690' UNION ALL
    SELECT '76695'
),
-- Count ultrasounds per admission
ultrasound_counts AS (
    SELECT 
        h.hadm_id,
        COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN ultrasound_codes uc ON h.hcpcs_cd = uc.code
    GROUP BY h.hadm_id
),
-- Final dataset with filtering and grouping
final_data AS (
    SELECT 
        a.hadm_id,
        a.age_at_admission,
        a.los_days,
        CASE 
            WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN a.los_days BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE 'Other' 
        END AS los_group,
        adt.acs_diagnosis_type,
        COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
    FROM admissions_with_age a
    INNER JOIN acs_diagnosis_type adt ON a.hadm_id = adt.hadm_id
    LEFT JOIN ultrasound_counts uc ON a.hadm_id = uc.hadm_id
    WHERE 
        a.age_at_admission BETWEEN 83 AND 93
        AND a.los_days BETWEEN 1 AND 7
)
-- Aggregate results
SELECT 
    los_group,
    acs_diagnosis_type,
    AVG(ultrasound_count) AS mean_ultrasounds,
    MIN(ultrasound_count) AS min_ultrasounds,
    MAX(ultrasound_count) AS max_ultrasounds
FROM final_data
WHERE los_group IN ('1-4 days', '5-7 days')
GROUP BY los_group, acs_diagnosis_type
ORDER BY los_group, acs_diagnosis_type;