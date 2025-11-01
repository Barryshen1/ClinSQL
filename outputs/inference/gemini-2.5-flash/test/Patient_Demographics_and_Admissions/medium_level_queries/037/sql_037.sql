WITH admissions_cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate Length of Stay in fractional days
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Determine outcome: 'Died' if hospital_expire_flag is 1, 'Alive' otherwise
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'Died'
            ELSE 'Alive'
        END AS outcome
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
        AND a.admission_type != 'EMERGENCY'
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND a.dischtime > a.admittime -- Exclude invalid or zero-length stays
)
SELECT
    outcome,
    -- Calculate LOS Percentiles for each outcome group
    ROUND(PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY outcome), 2) AS los_p50,
    ROUND(PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY outcome), 2) AS los_p75,
    ROUND(PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY outcome), 2) AS los_p90,
    ROUND(PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY outcome), 2) AS los_p95,
    -- Calculate the percentile rank of a 7-day LOS
    -- This represents the percentage of patients in each outcome group with LOS <= 7 days
    ROUND(
        SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) OVER (PARTITION BY outcome) * 100.0
        / COUNT(los_days) OVER (PARTITION BY outcome)
    , 2) AS percentile_rank_7_days
FROM
    admissions_cohort
-- Use QUALIFY to select only one row per outcome group, as window functions produce repeated values
QUALIFY ROW_NUMBER() OVER (PARTITION BY outcome ORDER BY outcome) = 1
ORDER BY
    outcome;