WITH male_inpatients AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate length of stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Check for AKI diagnosis during this admission
        MAX(CASE WHEN d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
    GROUP BY p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
aki_group AS (
    SELECT 
        'AKI' AS group_label,
        COUNT(*) AS num_patients,
        AVG(los_days) AS avg_los_days,
        AVG(hospital_expire_flag) * 100 AS mortality_percent,
        NULL AS mean_instability_score,   -- Cannot compute without definition
        NULL AS critical_event_frequency   -- Cannot compute without definition
    FROM male_inpatients
    WHERE has_aki = 1
),
control_group AS (
    SELECT 
        'Control' AS group_label,
        COUNT(*) AS num_patients,
        AVG(los_days) AS avg_los_days,
        AVG(hospital_expire_flag) * 100 AS mortality_percent,
        NULL AS mean_instability_score,   -- Cannot compute without definition
        NULL AS critical_event_frequency   -- Cannot compute without definition
    FROM male_inpatients
    WHERE has_aki = 0
)
SELECT * FROM aki_group
UNION ALL
SELECT * FROM control_group;