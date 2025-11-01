WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND a.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 86 AND 96
),
ugib_diagnoses AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        icd_code IN ('K25.9', 'K26.9', 'K27.9', 'K28.9', 'K92.2')
        AND icd_version = 10
),
copd_diagnoses AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        icd_code IN ('J44.1', 'J44.9')
        AND icd_version = 10
),
qualified_admissions AS (
    SELECT 
        pa.hadm_id,
        pa.los_days
    FROM patient_admissions pa
    INNER JOIN ugib_diagnoses u
        ON pa.hadm_id = u.hadm_id
    INNER JOIN copd_diagnoses c
        ON pa.hadm_id = c.hadm_id
)
SELECT 
    AVG(los_days) AS avg_los
FROM qualified_admissions;