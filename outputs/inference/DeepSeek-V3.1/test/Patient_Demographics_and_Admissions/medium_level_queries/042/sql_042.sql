WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admission_type,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Compute age at admission: use anchor_age directly (it's age at anchor_year, but for this cohort range it's sufficient)
        pt.anchor_age AS age_admit,
        pt.gender,
        -- Calculate LOS in days
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE 
        pt.gender = 'M'
        AND adm.admission_type IN ('EMERGENCY', 'URGENT')
        AND pt.anchor_age BETWEEN 57 AND 67
        -- Filter for medical admissions using the first service
        AND adm.hadm_id IN (
            SELECT hadm_id
            FROM (
                SELECT 
                    hadm_id,
                    curr_service,
                    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
                FROM `physionet-data.mimiciv_3_1_hosp.services`
            ) 
            WHERE rn = 1 AND curr_service = 'MEDICAL'
        )
),
-- Group by discharge status (alive vs death)
stats_by_group AS (
    SELECT 
        CASE 
            WHEN hospital_expire_flag = 0 THEN 'Discharged alive'
            ELSE 'In-hospital death'
        END AS discharge_status,
        COUNT(*) AS n_admissions,
        AVG(los) AS mean_los,
        APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
        APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
        APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
    FROM cohort
    GROUP BY hospital_expire_flag
),
-- Percentile rank of 5-day stay for entire cohort
percentile_rank AS (
    SELECT 
        CASE 
            WHEN COUNT(*) > 0 THEN COUNTIF(los <= 5) * 100.0 / COUNT(*)
            ELSE NULL 
        END AS percentile_rank_5_day
    FROM cohort
)
-- Combine both results
SELECT 
    discharge_status,
    n_admissions,
    mean_los,
    median_los,
    p75_los,
    p90_los
FROM stats_by_group
UNION ALL
SELECT 
    'Entire cohort' AS discharge_status,
    NULL AS n_admissions,
    NULL AS mean_los,
    NULL AS median_los,
    NULL AS p75_los,
    percentile_rank_5_day AS p90_los
FROM percentile_rank;