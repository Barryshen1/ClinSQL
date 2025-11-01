WITH heart_failure_patients AS (
    SELECT DISTINCT d.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE (d.icd_version = 9 AND d.icd_code LIKE '428%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),
patients_with_icu AS (
    SELECT subject_id, anchor_year, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
        AND anchor_year IS NOT NULL
        AND anchor_age IS NOT NULL
),
patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE(p.anchor_year - p.anchor_age, 1, 1) AS birth_date,
        TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), DAY) / 365.25 AS age_at_admission,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_with_icu p ON a.subject_id = p.subject_id
    WHERE a.dischtime IS NOT NULL
),
ranked_admissions AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM patient_admissions
),
first_admissions AS (
    SELECT 
        subject_id,
        los_days,
        age_at_admission
    FROM ranked_admissions
    WHERE rn = 1
),
eligible_patients AS (
    SELECT 
        f.subject_id,
        f.los_days
    FROM first_admissions f
    JOIN heart_failure_patients h ON f.subject_id = h.subject_id
    WHERE f.age_at_admission BETWEEN 79 AND 89
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM eligible_patients;