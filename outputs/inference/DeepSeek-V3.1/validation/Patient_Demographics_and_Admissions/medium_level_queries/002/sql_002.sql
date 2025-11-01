WITH medicine_admissions AS (
    SELECT DISTINCT s.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services` s
    WHERE s.curr_service = 'Medicine'
),
patient_cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN medicine_admissions m
        ON a.hadm_id = m.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 59 AND 69
),
discharge_groups AS (
    SELECT 
        hadm_id,
        los_days,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'Death'
            WHEN discharge_location LIKE '%HOME%' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_group
    FROM patient_cohort
)
SELECT 
    discharge_group,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los,
    APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los,
    ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_leq_10
FROM discharge_groups
GROUP BY discharge_group
ORDER BY discharge_group;