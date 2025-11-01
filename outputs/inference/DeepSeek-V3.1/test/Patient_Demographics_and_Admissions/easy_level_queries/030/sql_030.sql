WITH first_admission AS (
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
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
anticoagulant_patients AS (
    SELECT DISTINCT
        fa.subject_id,
        fa.hadm_id,
        fa.los_days
    FROM first_admission fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON fa.hadm_id = pr.hadm_id
    WHERE LOWER(pr.drug) LIKE '%warfarin%'
        OR LOWER(pr.drug) LIKE '%heparin%'
        OR LOWER(pr.drug) LIKE '%enoxaparin%'
        OR LOWER(pr.drug) LIKE '%apixaban%'
        OR LOWER(pr.drug) LIKE '%rivaroxaban%'
        OR LOWER(pr.drug) LIKE '%dabigatran%'
        OR LOWER(pr.drug) LIKE '%anticoagulant%'
)
SELECT 
    STDDEV(los_days) AS los_stddev
FROM anticoagulant_patients;