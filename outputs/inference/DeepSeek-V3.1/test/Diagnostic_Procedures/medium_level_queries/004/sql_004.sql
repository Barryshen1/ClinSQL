WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        -- Calculate LOS in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize HF: primary if any HF diagnosis has seq_num=1, else secondary
        MAX(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary_hf,
        -- LOS group: 1-3 vs 4-7 (using computed los_days)
        CASE 
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 45 AND 55
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.dischtime, adm.admittime
),

-- Count CT/MRI procedures per admission
proc_counts AS (
    SELECT 
        hadm_id,
        COUNT(DISTINCT proc.icd_code) AS ct_mri_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    WHERE 
        -- ICD-10 PCS: CT (codes starting with B?1) and MRI (B?3)
        (proc.icd_version = 10 AND (proc.icd_code LIKE 'B%1%' OR proc.icd_code LIKE 'B%3%')) OR
        -- ICD-9: CT (87.41) and MRI (88.38, 88.39, etc.)
        (proc.icd_version = 9 AND (proc.icd_code LIKE '87.41%' OR proc.icd_code LIKE '88.38%' OR proc.icd_code LIKE '88.39%'))
    GROUP BY hadm_id
)

-- Aggregate by HF type and LOS group
SELECT 
    CASE WHEN c.is_primary_hf = 1 THEN 'Primary HF' ELSE 'Secondary HF' END AS hf_type,
    c.los_group,
    COUNT(c.hadm_id) AS num_admissions,
    COALESCE(AVG(p.ct_mri_count), 0) AS mean_ct_mri_per_admission,
    COALESCE(MIN(p.ct_mri_count), 0) AS min_ct_mri_per_admission,
    COALESCE(MAX(p.ct_mri_count), 0) AS max_ct_mri_per_admission
FROM cohort c
LEFT JOIN proc_counts p
    ON c.hadm_id = p.hadm_id
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;