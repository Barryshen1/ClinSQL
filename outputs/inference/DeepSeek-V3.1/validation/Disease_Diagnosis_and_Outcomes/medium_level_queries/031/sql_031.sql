WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        MAX(CASE WHEN d.icd_code = 'R65.21' THEN 1 ELSE 0 END) AS septic_shock,
        MAX(CASE WHEN (d.icd_code LIKE 'R65.2%' OR d.icd_code LIKE 'A41%') 
                  AND d.icd_code != 'R65.21' THEN 1 ELSE 0 END) AS sepsis
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND (d.icd_code LIKE 'R65.2%' OR d.icd_code LIKE 'A41%')
    GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),
los_groups AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        deathtime,
        hospital_expire_flag,
        los_days,
        CASE WHEN septic_shock = 1 THEN 'Septic Shock' ELSE 'Sepsis' END AS condition_group,
        CASE WHEN los_days <= 7 THEN 'LOS ≤7' ELSE 'LOS >7' END AS los_group
    FROM cohort
    WHERE sepsis = 1 OR septic_shock = 1
),
aggregated AS (
    SELECT 
        condition_group,
        los_group,
        COUNT(*) AS n,
        SUM(hospital_expire_flag) AS deaths,
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_percent,
        PERCENTILE_CONT(
            CASE WHEN hospital_expire_flag = 1 
                 THEN DATETIME_DIFF(deathtime, admittime, HOUR) 
                 ELSE NULL END, 
            0.5
        ) AS median_time_to_death_hours
    FROM los_groups
    GROUP BY condition_group, los_group
)
SELECT 
    condition_group,
    los_group,
    n,
    deaths,
    mortality_percent,
    median_time_to_death_hours,
    -- Absolute mortality difference between LOS groups for each condition
    mortality_percent - LAG(mortality_percent) OVER (PARTITION BY condition_group ORDER BY los_group) AS absolute_mortality_diff,
    -- Relative mortality difference (percentage point change)
    SAFE_DIVIDE(
        mortality_percent - LAG(mortality_percent) OVER (PARTITION BY condition_group ORDER BY los_group),
        LAG(mortality_percent) OVER (PARTITION BY condition_group ORDER BY los_group)
    ) * 100 AS relative_mortality_diff_percent
FROM aggregated
ORDER BY condition_group, los_group;