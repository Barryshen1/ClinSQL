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
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND adm.admission_type != 'EMERGENCY'
        AND adm.dischtime IS NOT NULL
),
percentiles_by_group AS (
    SELECT
        hospital_expire_flag,
        APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
        APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
        APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
        APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
    FROM cohort
    GROUP BY hospital_expire_flag
),
percentile_rank_7days AS (
    SELECT
        hospital_expire_flag,
        PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_7days_rank
    FROM cohort
    WHERE los_days = 7
)
SELECT 
    pbg.hospital_expire_flag,
    pbg.p50,
    pbg.p75,
    pbg.p90,
    pbg.p95,
    pr.percentile_7days_rank
FROM percentiles_by_group pbg
LEFT JOIN percentile_rank_7days pr
    ON pbg.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY pbg.hospital_expire_flag;