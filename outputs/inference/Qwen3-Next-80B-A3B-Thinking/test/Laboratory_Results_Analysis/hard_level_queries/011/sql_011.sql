WITH aki_patients AS (
    SELECT DISTINCT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'N17%'
),
controls AS (
    SELECT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
        AND p.subject_id NOT IN (SELECT subject_id FROM aki_patients)
),
aki_group AS (
    SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.subject_id IN (SELECT subject_id FROM aki_patients)
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
),
control_group AS (
    SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.subject_id IN (SELECT subject_id FROM controls)
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
),
creatinine_aki AS (
    SELECT 
        a.subject_id,
        STDDEV(le.valuenum) AS creatinine_stddev
    FROM aki_group a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
    WHERE le.itemid = 50912
        AND le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '72 HOUR'
    GROUP BY a.subject_id
),
creatinine_control AS (
    SELECT 
        c.subject_id,
        STDDEV(le.valuenum) AS creatinine_stddev
    FROM control_group c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
    WHERE le.itemid = 50912
        AND le.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72 HOUR'
    GROUP BY c.subject_id
),
vasopressor_aki AS (
    SELECT 
        a.subject_id,
        MAX(CASE WHEN ie.itemid IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor
    FROM aki_group a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
        ON a.hadm_id = ie.hadm_id AND ie.itemid = 222315
    GROUP BY a.subject_id
),
vasopressor_control AS (
    SELECT 
        c.subject_id,
        MAX(CASE WHEN ie.itemid IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor
    FROM control_group c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
        ON c.hadm_id = ie.hadm_id AND ie.itemid = 222315
    GROUP BY c.subject_id
),
los_aki AS (
    SELECT 
        subject_id,
        TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600 / 24 AS los_days
    FROM aki_group
),
los_control AS (
    SELECT 
        subject_id,
        TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600 / 24 AS los_days
    FROM control_group
),
mortality_aki AS (
    SELECT 
        subject_id,
        hospital_expire_flag
    FROM aki_group
),
mortality_control AS (
    SELECT 
        subject_id,
        hospital_expire_flag
    FROM control_group
)
SELECT 
    'AKI' AS group_type,
    AVG(creatinine_stddev) AS mean_lab_instability,
    AVG(has_vasopressor) AS critical_event_frequency,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM creatinine_aki
JOIN vasopressor_aki USING (subject_id)
JOIN los_aki USING (subject_id)
JOIN mortality_aki USING (subject_id)
UNION ALL
SELECT 
    'Control' AS group_type,
    AVG(creatinine_stddev) AS mean_lab_instability,
    AVG(has_vasopressor) AS critical_event_frequency,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM creatinine_control
JOIN vasopressor_control USING (subject_id)
JOIN los_control USING (subject_id)
JOIN mortality_control USING (subject_id);