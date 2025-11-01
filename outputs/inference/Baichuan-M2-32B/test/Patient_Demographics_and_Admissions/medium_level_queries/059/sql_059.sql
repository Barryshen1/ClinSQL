WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        a.hospital_expire_flag,
        a.discharge_location
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 75 AND 85
        AND a.admission_location = 'Transfer from another hospital'
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND (a.hospital_expire_flag = 1 
             OR a.discharge_location IN ('Home', 'Hospice care'))
),
counts AS (
    SELECT 
        COUNT(*) AS total_admissions,
        SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS long_stay_count
    FROM cohort
),
percentile AS (
    SELECT 
        APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los
    FROM cohort
)
SELECT 
    total_admissions,
    long_stay_count,
    1.0 * long_stay_count / total_admissions AS proportion,
    p75_los
FROM counts, percentile;