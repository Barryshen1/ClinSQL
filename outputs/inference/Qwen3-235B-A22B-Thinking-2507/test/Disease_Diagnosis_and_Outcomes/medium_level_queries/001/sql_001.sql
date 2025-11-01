WITH base AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 67 AND 77
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_version = 10
                AND d.icd_code IN ('I50.810', 'I50.811', 'I50.812', 'I50.813', 'I50.814', 'I50.84')
        )
),
admissions_with_los AS (
    SELECT 
        base.*,
        DATETIME_DIFF(base.dischtime, base.admittime, DAY) AS los_days,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
                WHERE i.hadm_id = base.hadm_id 
                    AND i.intime < DATETIME_ADD(base.admittime, INTERVAL 1 DAY)
            ) THEN 1 
            ELSE 0 
        END AS day1_icu
    FROM base
),
admissions_with_conditions AS (
    SELECT 
        a.*,
        MAX(CASE WHEN d.icd_code IN ('N18.1','N18.2','N18.3','N18.4','N18.5','N18.6','N18.9') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_diabetes
    FROM admissions_with_los a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.gender, a.anchor_age, a.anchor_year, a.los_days, a.day1_icu
)
SELECT
    CASE WHEN los_days <= 7 THEN '≤7' ELSE '>7' END AS los_group,
    day1_icu,
    COUNT(*) AS total_patients,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
    ROUND(SUM(has_ckd) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
    ROUND(SUM(has_diabetes) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM admissions_with_conditions
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;