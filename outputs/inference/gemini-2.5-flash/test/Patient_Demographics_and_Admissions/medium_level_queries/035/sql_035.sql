SELECT
    admission_cohort.discharge_outcome,
    COUNT(admission_cohort.hadm_id) AS num_admissions,
    -- Calculate Median Length of Stay
    APPROX_QUANTILES(admission_cohort.los_days, 100)[OFFSET(50)] AS median_los_days,
    -- Calculate Interquartile Range (IQR) of Length of Stay
    (APPROX_QUANTILES(admission_cohort.los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(admission_cohort.los_days, 100)[OFFSET(25)]) AS iqr_los_days,
    -- Calculate Percentile Rank of a 14-day stay
    -- This represents the percentage of stays that were 14 days or less.
    SAFE_DIVIDE(SUM(CASE WHEN admission_cohort.los_days <= 14 THEN 1 ELSE 0 END) * 100.0, COUNT(admission_cohort.los_days)) AS percentile_rank_14_day_stay
FROM
    (
        SELECT
            p.subject_id,
            a.hadm_id,
            -- Calculate precise age at admission
            p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
            -- Calculate Length of Stay in days
            DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
            -- Categorize discharge outcome
            CASE
                WHEN a.hospital_expire_flag = 1 THEN 'Death'
                WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST ADVICE') THEN 'Home'
                ELSE 'Facility' -- Covers SNF, LTC, Rehab, other hospitals, etc.
            END AS discharge_outcome
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON a.subject_id = p.subject_id
        WHERE
            p.gender = 'F'
            AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
            AND a.admission_location = 'EMERGENCY ROOM ADMIT' -- Admitted from ED
            AND a.admittime IS NOT NULL
            AND a.dischtime IS NOT NULL
            AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0 -- Ensure valid LOS
    ) AS admission_cohort
GROUP BY
    admission_cohort.discharge_outcome
ORDER BY
    admission_cohort.discharge_outcome;