WITH cohort AS (
    SELECT 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        adm.deathtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- For non-survivors, compute time to death in days (as float for median)
        CASE WHEN adm.hospital_expire_flag = 1 THEN 
            DATE_DIFF(adm.deathtime, adm.admittime, DAY) 
        ELSE NULL END AS time_to_death
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 70 AND 80
        AND (
            diag.icd_code LIKE 'I50%' OR  -- ICD-10 Heart Failure
            diag.icd_code LIKE '428%'     -- ICD-9 Heart Failure
        )
        AND diag.icd_version IN (9,10)
)

SELECT 
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COUNT(*) AS admission_count,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent,
    -- Compute median time to death only for non-survivors in each group
    APPROX_QUANTILES(time_to_death, 100 RESPECT NULLS)[OFFSET(50)] AS median_time_to_death_days
FROM cohort
GROUP BY los_group
ORDER BY los_group;