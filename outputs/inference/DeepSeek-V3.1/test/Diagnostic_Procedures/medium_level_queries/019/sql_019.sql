WITH pancreatitis_admissions AS (
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
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
        AND (
            (dd.icd_version = 10 AND dd.icd_code LIKE 'K85%') 
            OR (dd.icd_version = 9 AND dd.icd_code = '577.0')
        )
),
procedures_per_admission AS (
    SELECT 
        pa.hadm_id,
        pa.los_days,
        CASE 
            WHEN pa.los_days BETWEEN 1 AND 4 THEN '1-4'
            WHEN pa.los_days BETWEEN 5 AND 7 THEN '5-7'
        END AS los_group,
        COUNT(DISTINCT picd.icd_code) AS num_procedures
    FROM pancreatitis_admissions pa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON pa.hadm_id = picd.hadm_id
    WHERE pa.los_days BETWEEN 1 AND 7  -- Only include LOS 1-7 as per question
    GROUP BY pa.hadm_id, pa.los_days
)
SELECT 
    los_group,
    COUNT(hadm_id) AS patient_count,
    ROUND(AVG(num_procedures), 2) AS mean_procedures,
    MIN(num_procedures) AS min_procedures,
    MAX(num_procedures) AS max_procedures
FROM procedures_per_admission
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;