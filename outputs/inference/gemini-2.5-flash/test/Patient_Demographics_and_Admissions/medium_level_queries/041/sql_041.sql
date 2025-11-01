SELECT
    discharge_outcome,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    CAST(AVG(los_days) AS BIGNUMERIC) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
    CAST(COUNTIF(los_days <= 7) * 100.0 / COUNT(los_days) AS BIGNUMERIC) AS percent_los_le_7_days
FROM (
    SELECT
        a.subject_id,
        a.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE
            WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
            WHEN LOWER(a.discharge_location) LIKE '%snf%'
                OR LOWER(a.discharge_location) LIKE '%rehab%'
                OR LOWER(a.discharge_location) LIKE '%ltach%' THEN 'SNF/rehab/LTACH'
            WHEN a.discharge_location = 'Dead/Expired' THEN 'in-hospital death'
            ELSE 'Other' -- Catch all other discharge locations
        END AS discharge_outcome
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98 -- Age 88-98
        AND a.admission_type = 'ELECTIVE'
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0 -- Ensure non-negative LOS
)
WHERE
    discharge_outcome IN ('home', 'SNF/rehab/LTACH', 'in-hospital death') -- Only include specified outcomes
GROUP BY
    discharge_outcome
ORDER BY
    discharge_outcome;