WITH eligible_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 64 AND 74
        AND a.dischtime IS NOT NULL
),
sepsis_admissions AS (
    SELECT 
        e.*
    FROM eligible_admissions e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON e.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
        dd.icd_version = 10
        AND d.icd_code IN (
            'A40.1', 'A40.2', 'A40.3', 'A40.4', 'A40.5', 'A40.6', 'A40.7', 'A40.8', 'A40.9',
            'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.6', 'A41.7', 'A41.8', 'A41.9'
        )
    GROUP BY e.subject_id, e.hadm_id, e.admittime, e.dischtime, e.hospital_expire_flag, e.age_at_admission
    HAVING COUNT(DISTINCT d.icd_code) >= 1
),
los_calculated AS (
    SELECT 
        *,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days
    FROM sepsis_admissions
),
los_quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM los_calculated
),
ckd_diabetes_flags AS (
    SELECT 
        l.*,
        MAX(CASE WHEN d.icd_code IN (
            'N18.1', 'N18.3', 'N18.5', 'N18.6', 'N18.9', 'N19.0', 'N19.1', 'N19.2', 'N19.3', 'N19.4', 'N19.5', 'N19.6', 'N19.7', 'N19.8', 'N19.9'
        ) THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN d.icd_code IN (
            'E10', 'E11', 'E12', 'E13', 'E14', 'E15', 'E16', 'E17', 'E18', 'E19', 'E20', 'E21', 'E22', 'E23', 'E24', 'E25', 'E26', 'E27', 'E28', 'E29', 'E30', 'E31', 'E32', 'E33', 'E34', 'E35', 'E36', 'E37', 'E38', 'E39', 'E40', 'E41', 'E42', 'E43', 'E44', 'E45', 'E46', 'E47', 'E48', 'E49', 'E50', 'E51', 'E52', 'E53', 'E54', 'E55', 'E56', 'E57', 'E58', 'E59', 'E60', 'E61', 'E62', 'E63', 'E64', 'E65', 'E66', 'E67', 'E68', 'E69', 'E70', 'E71', 'E72', 'E73', 'E74', 'E75', 'E76', 'E77', 'E78', 'E79', 'E80', 'E81', 'E82', 'E83', 'E84', 'E85', 'E86', 'E87', 'E88', 'E89', 'E90', 'E91', 'E92', 'E93', 'E94', 'E95', 'E96', 'E97', 'E98', 'E99'
        ) THEN 1 ELSE 0 END) AS has_diabetes
    FROM los_quartiles l
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON l.hadm_id = d.hadm_id
    WHERE d.icd_version = 10
    GROUP BY l.subject_id, l.hadm_id, l.admittime, l.dischtime, l.hospital_expire_flag, l.age_at_admission, l.los_days, l.los_quartile
)
SELECT 
    los_quartile,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
    SUM(has_ckd) / COUNT(*) AS ckd_prevalence,
    SUM(has_diabetes) / COUNT(*) AS diabetes_prevalence
FROM ckd_diabetes_flags
GROUP BY los_quartile
ORDER BY los_quartile;