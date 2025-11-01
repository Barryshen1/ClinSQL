WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.discharge_location,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 43 AND 53
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND adm.dischtime > adm.admittime  -- sanity check
),
discharge_groups AS (
    SELECT 
        hadm_id,
        los_days,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'Death'
            WHEN discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_outcome
    FROM cohort
)
SELECT 
    discharge_outcome,
    COUNT(*) AS n_patients,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS q1_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS q3_los_days,
    ROUND(100 * AVG(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END), 2) AS percentile_rank_14d
FROM discharge_groups
GROUP BY discharge_outcome
ORDER BY discharge_outcome;