WITH pancreatitis_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 47 AND 57
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%') 
            OR (diag.icd_version = 9 AND diag.icd_code = '5770')
        )
),
ct_mri_procedures AS (
    SELECT 
        proc.hadm_id,
        COUNT(DISTINCT proc.icd_code) AS num_procedures  -- Count distinct procedures per admission
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        LOWER(dicd.long_title) LIKE '%computed tomography%'
        OR LOWER(dicd.long_title) LIKE '%magnetic resonance%'
    GROUP BY proc.hadm_id
)
SELECT 
    pa.los_group,
    COUNT(DISTINCT pa.hadm_id) AS patient_count,
    AVG(COALESCE(cmp.num_procedures, 0)) AS mean_ct_mri_procedures
FROM pancreatitis_admissions pa
LEFT JOIN ct_mri_procedures cmp
    ON pa.hadm_id = cmp.hadm_id
WHERE pa.los_group IN ('1-4', '5-8')
GROUP BY pa.los_group
ORDER BY pa.los_group;