WITH sepsis_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'A41%'  -- sepsis codes
    AND d.icd_version = 10
    AND a.hadm_id NOT IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code = 'R65.21' AND icd_version = 10  -- exclude septic shock
    )
),
cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.deathtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 'LOS <=7'
             ELSE 'LOS >7' END AS los_group,
        -- Time to death in days for those who died in hospital
        CASE WHEN a.hospital_expire_flag = 1 THEN DATE_DIFF(a.deathtime, a.admittime, DAY) END AS time_to_death_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN sepsis_admissions s
        ON a.hadm_id = s.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
)
SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    -- Median time to death (only for those who died) - using approx_quantiles
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
FROM cohort
GROUP BY los_group
ORDER BY los_group;