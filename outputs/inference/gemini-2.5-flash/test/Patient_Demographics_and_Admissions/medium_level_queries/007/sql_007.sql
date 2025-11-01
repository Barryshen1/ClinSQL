WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Calculate Length of Stay in days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Calculate age at admission using anchor_age and year difference
        pa.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pa.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON adm.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        -- Filter for patients transferred from another hospital
        AND adm.admission_location = 'TRANSFER FROM OTHER HEAL FAC'
        -- Filter for age at admission between 78 and 88 years
        AND (pa.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pa.anchor_year)) BETWEEN 78 AND 88
        -- Ensure LOS is not null (i.e., dischtime is not null for calculation) and positive
        -- LOS needs dischtime to be non-null. TIMESTAMP_DIFF returns NULL if either argument is NULL.
        AND adm.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) >= 0 -- Ensure non-negative LOS
)
SELECT
    CASE
        WHEN hospital_expire_flag = 1 THEN 'Died In-Hospital'
        ELSE 'Survived'
    END AS outcome,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    -- Calculate Length of Stay percentiles using APPROX_QUANTILES
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS los_p95,
    -- Calculate percentile rank of a 10-day LOS (i.e., percentage of admissions with LOS <= 10 days)
    SAFE_DIVIDE(
        COUNT(CASE WHEN los_days <= 10 THEN 1 END),
        COUNT(los_days)
    ) * 100 AS los_10_day_percentile_rank
FROM
    cohort_admissions
GROUP BY
    hospital_expire_flag -- Group by the flag to stratify by outcome
ORDER BY
    hospital_expire_flag;