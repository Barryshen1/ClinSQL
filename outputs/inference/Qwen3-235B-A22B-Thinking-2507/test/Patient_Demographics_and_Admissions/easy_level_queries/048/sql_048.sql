WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE a.dischtime IS NOT NULL
),
heart_failure AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '428%')
        OR 
        (icd_version = 10 AND icd_code LIKE 'I50%')
),
filtered AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        fa.anchor_age + (EXTRACT(YEAR FROM fa.admittime) - fa.anchor_year) AS age_at_admission,
        TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND) / (24*60*60) AS los_days
    FROM first_admissions fa
    INNER JOIN heart_failure hf
        ON fa.hadm_id = hf.hadm_id
    WHERE 
        fa.rn = 1
        AND fa.gender = 'F'
        AND (fa.anchor_age + (EXTRACT(YEAR FROM fa.admittime) - fa.anchor_year)) BETWEEN 79 AND 89
)
SELECT 
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr_los
FROM filtered;