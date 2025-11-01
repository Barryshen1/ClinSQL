WITH cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admission_type,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        -- Calculate length of stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Classify discharge status: alive vs died in hospital
        CASE
            WHEN adm.deathtime IS NOT NULL OR adm.hospital_expire_flag = 1 THEN 'died'
            ELSE 'alive'
        END AS discharge_status,
        -- Flag for LOS >= 7 days
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 7 THEN 1
            ELSE 0
        END AS los_ge_7
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND adm.admission_type = 'EMERGENCY'
        AND adm.dischtime IS NOT NULL  -- Exclude ongoing admissions
),
los_stats AS (
    SELECT
        discharge_status,
        COUNT(*) AS total_patients,
        SUM(los_ge_7) AS count_los_ge_7,
        -- Proportion with LOS >=7 by discharge status
        ROUND(SUM(los_ge_7) * 100.0 / COUNT(*), 2) AS proportion_los_ge_7_percent
    FROM cohort
    GROUP BY discharge_status
),
percentile_rank AS (
    SELECT
        -- Calculate percentile rank of a 7-day LOS in the entire cohort
        ROUND(PERCENT_RANK() OVER (ORDER BY los_days) * 100, 2) AS percentile_rank_7_day_los
    FROM cohort
    WHERE los_days = 7
    LIMIT 1  -- Since all rows with los_days=7 have the same percentile rank
)
SELECT
    los_stats.discharge_status,
    los_stats.total_patients,
    los_stats.count_los_ge_7,
    los_stats.proportion_los_ge_7_percent,
    percentile_rank.percentile_rank_7_day_los
FROM los_stats
CROSS JOIN percentile_rank
ORDER BY los_stats.discharge_status;