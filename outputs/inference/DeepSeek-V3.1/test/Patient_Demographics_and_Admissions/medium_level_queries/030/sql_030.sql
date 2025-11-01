WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND adm.admission_type = 'ELECTIVE'
        AND adm.dischtime IS NOT NULL
        AND adm.dischtime >= adm.admittime
)
SELECT 
    CASE 
        WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
        ELSE 'Discharged Alive'
    END AS outcome,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY outcome;