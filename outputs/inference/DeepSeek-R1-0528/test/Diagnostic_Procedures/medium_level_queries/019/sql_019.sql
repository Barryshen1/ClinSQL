WITH base_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admission,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE 
                adm.hadm_id = diag.hadm_id
                AND (
                    (diag.icd_version = 9 AND diag.icd_code LIKE '5770%') 
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
                )
        )
),
filtered_cohort AS (
    SELECT 
        subject_id,
        hadm_id,
        los_days,
        CASE 
            WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
            WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
        END AS los_group
    FROM base_cohort
    WHERE 
        age_admission BETWEEN 42 AND 52
        AND los_days BETWEEN 1 AND 7
),
procedures_per_admission AS (
    SELECT 
        hadm_id, 
        COUNT(*) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
)
SELECT 
    f.los_group,
    COUNT(DISTINCT f.subject_id) AS patient_count,
    ROUND(AVG(COALESCE(p.num_procedures, 0)), 1) AS mean_procedures,
    MIN(COALESCE(p.num_procedures, 0)) AS min_procedures,
    MAX(COALESCE(p.num_procedures, 0)) AS max_procedures
FROM filtered_cohort f
LEFT JOIN procedures_per_admission p
    ON f.hadm_id = p.hadm_id
GROUP BY f.los_group
ORDER BY f.los_group;