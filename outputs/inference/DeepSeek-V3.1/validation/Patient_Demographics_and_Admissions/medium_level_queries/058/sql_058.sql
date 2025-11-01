WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admission_type,
        adm.admission_location,
        adm.discharge_location,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN adm.discharge_location = 'HOME' THEN 'Home'
            WHEN adm.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital mortality'
            ELSE 'Other'
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 37 AND 47
        AND adm.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
        AND adm.dischtime IS NOT NULL
        AND adm.admittime IS NOT NULL
),
percentile_rank_5day AS (
    SELECT 
        PERCENT_RANK() OVER (ORDER BY los_days) * 100 AS percentile_rank
    FROM cohort
    WHERE los_days = 5
    LIMIT 1
)
SELECT 
    discharge_category,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100) [SAFE_ORDINAL(25)] AS p25,
    APPROX_QUANTILES(los_days, 100) [SAFE_ORDINAL(50)] AS median,
    APPROX_QUANTILES(los_days, 100) [SAFE_ORDINAL(75)] AS p75,
    APPROX_QUANTILES(los_days, 100) [SAFE_ORDINAL(90)] AS p90,
    APPROX_QUANTILES(los_days, 100) [SAFE_ORDINAL(95)] AS p95
FROM cohort
WHERE discharge_category IN ('Home', 'SNF/rehab/LTACH', 'In-hospital mortality')
GROUP BY discharge_category

UNION ALL

SELECT 
    'Percentile rank of 5-day stay' AS discharge_category,
    (SELECT percentile_rank FROM percentile_rank_5day) AS n,
    NULL AS mean_los,
    NULL AS p25,
    NULL AS median,
    NULL AS p75,
    NULL AS p90,
    NULL AS p95;