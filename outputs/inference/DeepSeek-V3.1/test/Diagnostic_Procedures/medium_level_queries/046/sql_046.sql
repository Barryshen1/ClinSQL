WITH tia_patients AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
        AND d.icd_code LIKE 'G45%'   -- ICD-10 for TIA
        -- Alternatively, include ICD-9: OR d.icd_code LIKE '435%'
        AND d.icd_version = 10
),
ct_mri_procedures AS (
    SELECT 
        hadm_id,
        COUNT(*) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
        d.long_title LIKE '%computed tomography%' 
        OR d.long_title LIKE '%magnetic resonance%'
    GROUP BY hadm_id
),
combined AS (
    SELECT 
        tp.hadm_id,
        tp.los_days,
        CASE 
            WHEN tp.los_days BETWEEN 1 AND 3 THEN '1-3'
            WHEN tp.los_days BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other'
        END AS los_group,
        COALESCE(cp.procedure_count, 0) AS procedure_count
    FROM tia_patients tp
    LEFT JOIN ct_mri_procedures cp
        ON tp.hadm_id = cp.hadm_id
    WHERE tp.los_days BETWEEN 1 AND 7
)
SELECT 
    los_group,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(procedure_count) AS mean_procedures_per_admission
FROM combined
GROUP BY los_group
ORDER BY los_group;