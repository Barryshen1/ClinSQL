WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admission_type,
        adm.discharge_location,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN adm.discharge_location LIKE '%HOME%' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_outcome
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 37 AND 47
        AND adm.admission_type IN ('URGENT', 'EMERGENCY')
        AND adm.dischtime IS NOT NULL
        AND adm.admittime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
),
percentiles AS (
    SELECT
        discharge_outcome,
        COUNT(*) AS n,
        AVG(los_days) AS mean_los,
        APPROX_QUANTILES(los_days, 100) [OFFSET(25)] AS p25,
        APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS p50,
        APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS p75
    FROM cohort
    GROUP BY discharge_outcome
),
perc_rank AS (
    SELECT
        discharge_outcome,
        PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los_days) * 100 AS pct_rank
    FROM cohort
    WHERE los_days = 7
)
SELECT 
    p.discharge_outcome,
    p.n,
    p.mean_los,
    p.p25,
    p.p50,
    p.p75,
    pr.pct_rank AS percentile_rank_7_day_stay
FROM percentiles p
LEFT JOIN perc_rank pr
    ON p.discharge_outcome = pr.discharge_outcome
ORDER BY p.discharge_outcome;