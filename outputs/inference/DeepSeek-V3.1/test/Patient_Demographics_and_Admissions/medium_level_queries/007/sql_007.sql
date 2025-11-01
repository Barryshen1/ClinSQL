WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 78 AND 88
        AND adm.admission_location LIKE '%Transfer from%Hospital%'
        AND adm.dischtime IS NOT NULL
),
los_percentiles AS (
    SELECT
        hospital_expire_flag,
        COUNT(*) AS num_admissions,
        APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS p50_los,
        APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS p75_los,
        APPROX_QUANTILES(los_days, 100) [OFFSET(90)] AS p90_los,
        APPROX_QUANTILES(los_days, 100) [OFFSET(95)] AS p95_los
    FROM cohort
    GROUP BY hospital_expire_flag
),
percentile_rank AS (
    SELECT
        PERCENT_RANK() OVER (ORDER BY los_days) AS p_rank
    FROM cohort
    WHERE los_days = 10
    LIMIT 1
)
SELECT 
    los_percentiles.hospital_expire_flag,
    los_percentiles.num_admissions,
    los_percentiles.p50_los,
    los_percentiles.p75_los,
    los_percentiles.p90_los,
    los_percentiles.p95_los,
    (SELECT p_rank FROM percentile_rank) AS percentile_rank_10_day_los
FROM los_percentiles
ORDER BY hospital_expire_flag;