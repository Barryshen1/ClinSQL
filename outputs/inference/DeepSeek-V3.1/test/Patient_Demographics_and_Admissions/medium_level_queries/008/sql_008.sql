WITH base AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        adm.discharge_location,
        adm.admission_type,
        pt.gender,
        pt.anchor_age,
        -- Calculate LOS in days (fractional)
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize discharge group
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN 'Death'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
            ELSE 'Facility'
        END AS discharge_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    -- Filter for medicine patients: hadm_id must be in medicine services
    WHERE adm.hadm_id IN (
        SELECT hadm_id 
        FROM `physionet-data.mimiciv_3_1_hosp.services` 
        WHERE curr_service LIKE 'MED%'
    )
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 52 AND 62
    AND adm.admission_type IN ('URGENT', 'EMERGENCY')
    AND adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
),
agg AS (
    SELECT 
        discharge_group,
        COUNT(*) AS num_patients,
        AVG(los_days) AS mean_los,
        APPROX_QUANTILES(los_days, 100) AS quantiles
    FROM base
    GROUP BY discharge_group
)
SELECT 
    discharge_group,
    num_patients,
    mean_los,
    quantiles[OFFSET(50)] AS median_los,
    quantiles[OFFSET(75)] AS p75_los,
    quantiles[OFFSET(90)] AS p90_los,
    (SELECT AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) 
     FROM base b 
     WHERE b.discharge_group = agg.discharge_group) AS percentile_rank_7
FROM agg
ORDER BY discharge_group;