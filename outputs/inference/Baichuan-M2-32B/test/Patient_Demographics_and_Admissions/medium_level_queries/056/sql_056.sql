WITH patient_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.admission_type,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        -- Compute birthdate: Jan 1 of anchor_year minus anchor_age years
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birthdate
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        a.admission_type = 'Emergency'
        AND p.gender = 'M'
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND p.anchor_year IS NOT NULL
        AND p.anchor_age IS NOT NULL
),
age_computed AS (
    SELECT 
        *,
        TIMESTAMP_DIFF(admittime, birthdate, YEAR) AS age_at_admission
    FROM patient_admissions
),
filtered AS (
    SELECT 
        *,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
    FROM age_computed
    WHERE 
        age_at_admission BETWEEN 67 AND 77
)
SELECT 
    hospital_expire_flag AS discharge_status,
    COUNT(*) AS total_patients,
    AVG(IF(los >= 7, 1.0, 0.0)) AS proportion_los_ge_7,
    AVG(IF(los >= 14, 1.0, 0.0)) AS proportion_los_ge_14,
    AVG(IF(los <= 10, 1.0, 0.0)) AS percentile_rank_10_day_los
FROM filtered
GROUP BY discharge_status
ORDER BY discharge_status;