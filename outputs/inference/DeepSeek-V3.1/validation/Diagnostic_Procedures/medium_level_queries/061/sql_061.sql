WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        diag.icd_code,
        diag.icd_version,
        diag.seq_num,
        CASE 
            WHEN diag.seq_num = 1 THEN 'Primary'
            ELSE 'Secondary'
        END AS aki_priority
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') 
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
        )
        AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
    SELECT 
        c.hadm_id,
        c.aki_priority,
        c.los_days,
        COUNT(DISTINCT proc.icd_code) AS num_imaging_studies
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON c.hadm_id = proc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        LOWER(dicd.long_title) LIKE '%ct%' 
        OR LOWER(dicd.long_title) LIKE '%mri%'
        OR LOWER(dicd.long_title) LIKE '%x-ray%'
        OR LOWER(dicd.long_title) LIKE '%ultrasound%'
        OR LOWER(dicd.long_title) LIKE '%angiogram%'
        OR LOWER(dicd.long_title) LIKE '%fluoroscopy%'
    GROUP BY c.hadm_id, c.aki_priority, c.los_days
),
los_groups AS (
    SELECT 
        hadm_id,
        aki_priority,
        num_imaging_studies,
        CASE 
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
        END AS los_group
    FROM imaging_counts
)
SELECT 
    aki_priority,
    los_group,
    APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(2)] AS median,
    APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(3)] AS q3,
    COUNT(*) AS num_admissions
FROM los_groups
GROUP BY aki_priority, los_group
ORDER BY aki_priority, los_group;