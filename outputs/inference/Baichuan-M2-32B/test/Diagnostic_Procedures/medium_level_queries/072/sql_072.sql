WITH patient_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 52 AND 62
        AND a.dischtime IS NOT NULL
),
pancreatitis_admissions AS (
    SELECT 
        pa.hadm_id,
        pa.subject_id,
        pa.admittime,
        pa.dischtime,
        TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
        CASE 
            WHEN d.seq_num = 1 THEN 'Primary'
            ELSE 'Secondary'
        END AS primary_secondary
    FROM patient_admissions pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
        dd.icd_code LIKE 'K85%' 
        AND d.icd_version = 10
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY d.seq_num) = 1
),
diagnostic_procedures AS (
    SELECT 
        p.hadm_id,
        p.subject_id,
        p.chartdate
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
    WHERE 
        p.icd_version = 10
        AND (
            LOWER(dp.long_title) LIKE '%diagnostic%' 
            OR LOWER(dp.long_title) LIKE '%imaging%' 
            OR LOWER(dp.long_title) LIKE '%scan%' 
            OR LOWER(dp.long_title) LIKE '%ultrasound%' 
            OR LOWER(dp.long_title) LIKE '%x-ray%' 
            OR LOWER(dp.long_title) LIKE '%mri%' 
            OR LOWER(dp.long_title) LIKE '%ct%' 
            OR LOWER(dp.long_title) LIKE '%endoscopy%'
        )
),
procedures_per_admission AS (
    SELECT 
        pa.hadm_id,
        COUNT(dp.hadm_id) AS num_procedures
    FROM pancreatitis_admissions pa
    LEFT JOIN diagnostic_procedures dp 
        ON pa.subject_id = dp.subject_id AND pa.hadm_id = dp.hadm_id
        AND dp.chartdate BETWEEN pa.admittime AND pa.dischtime
    GROUP BY pa.hadm_id
),
los_categories AS (
    SELECT 
        ppa.hadm_id,
        ppa.primary_secondary,
        CASE 
            WHEN ppa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN ppa.los_days BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE NULL
        END AS los_category,
        ppaa.num_procedures
    FROM pancreatitis_admissions ppa
    INNER JOIN procedures_per_admission ppaa 
        ON ppa.hadm_id = ppaa.hadm_id
    WHERE 
        ppa.los_days BETWEEN 1 AND 8  -- only consider LOS 1-8 days
)
SELECT 
    los_category,
    primary_secondary,
    AVG(num_procedures) AS mean_procedures,
    MIN(num_procedures) AS min_procedures,
    MAX(num_procedures) AS max_procedures
FROM los_categories
GROUP BY los_category, primary_secondary
ORDER BY los_category, primary_secondary;