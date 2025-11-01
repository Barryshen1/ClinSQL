WITH acs_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        diag.icd_version = 10
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code = 'I20.0')
        AND pat.gender = 'M'
        AND pat.anchor_age BETWEEN 35 AND 45
),
ultrasound_procedures AS (
    SELECT 
        hadm_id,
        COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        dicd.long_title LIKE '%ultrasound%' 
        OR dicd.long_title LIKE '%echocardiography%'
    GROUP BY hadm_id
)
SELECT 
    los_group,
    COUNT(DISTINCT acs.hadm_id) AS patient_count,
    COALESCE(AVG(us.ultrasound_count), 0) AS mean_ultrasounds_per_admission
FROM acs_admissions acs
LEFT JOIN ultrasound_procedures us
    ON acs.hadm_id = us.hadm_id
WHERE los_group IN ('1-3 days', '4-7 days')
GROUP BY los_group
ORDER BY los_group;