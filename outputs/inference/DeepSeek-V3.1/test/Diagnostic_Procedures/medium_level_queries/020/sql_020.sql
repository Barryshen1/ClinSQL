WITH tia_patients AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other' 
        END AS los_group,
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu`.icustays icu 
            WHERE icu.hadm_id = a.hadm_id
        ) AS had_icu
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 72 AND 82
        AND d.long_title LIKE '%Transient ischemic attack%'
),
imaging_procedures AS (
    SELECT 
        hadm_id,
        COUNT(DISTINCT proc.icd_code) AS imaging_count  -- Count distinct procedures per admission
    FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dip
        ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
    WHERE LOWER(dip.long_title) LIKE '%imaging%'
        OR LOWER(dip.long_title) LIKE '%scan%'
        OR LOWER(dip.long_title) LIKE '%ultrasound%'
        OR LOWER(dip.long_title) LIKE '%x-ray%'
        OR LOWER(dip.long_title) LIKE '%radiograph%'
        OR LOWER(dip.long_title) LIKE '%mri%'
        OR LOWER(dip.long_title) LIKE '%ct%'
        OR LOWER(dip.long_title) LIKE '%angiogram%'
    GROUP BY hadm_id
)
SELECT 
    tp.los_group,
    tp.had_icu,
    COUNT(DISTINCT tp.hadm_id) AS admission_count,
    ROUND(AVG(COALESCE(ip.imaging_count, 0)), 2) AS mean_imaging_procedures
FROM tia_patients tp
LEFT JOIN imaging_procedures ip
    ON tp.hadm_id = ip.hadm_id
WHERE tp.los_group IN ('1-3', '4-7')
GROUP BY tp.los_group, tp.had_icu
ORDER BY tp.los_group, tp.had_icu;