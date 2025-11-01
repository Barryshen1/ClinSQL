WITH PatientCohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        -- Corrected: to identify "transfer-ins", use LIKE 'TRANSFER FROM%' for admission_type
        AND a.admission_type LIKE 'TRANSFER FROM%'
        -- Ensure valid LOS data: discharge time exists and is after admission time
        AND a.dischtime IS NOT NULL
        AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 0
),
DischargeCategorized AS (
    SELECT
        los_days,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
            WHEN discharge_location = 'Home' THEN 'Home'
            -- Group various discharge locations into 'SNF/rehab/LTACH'
            WHEN discharge_location IN (
                'Skilled Nursing Facility', 'Rehabilitation Hospital', 'Long Term Care Hospital',
                'SNF', 'Rehab', 'LTACH', 'Nursing Home', 'Assisted Living',
                'Hospice', 'Other Healthcare Facility', 'Chronic Hospital'
            ) THEN 'SNF/rehab/LTACH'
            ELSE 'Other/Exclude' -- Exclude discharge types not explicitly requested
        END AS discharge_group
    FROM
        PatientCohort
)
SELECT
    discharge_group,
    COUNT(*) AS n,
    ROUND(AVG(los_days), 2) AS mean_los,
    -- Replaced PERCENTILE_CONT with APPROX_QUANTILES for BigQuery compatibility
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los, -- Median is p50
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(95)], 2) AS p95_los,
    ROUND(
        (COUNTIF(los_days <= 5.0) * 100.0 / COUNT(*)), 2
    ) AS percentile_rank_of_5_day_stay -- Percentage of stays that are 5 days or shorter
FROM
    DischargeCategorized
WHERE
    discharge_group != 'Other/Exclude'
GROUP BY
    discharge_group
ORDER BY
    discharge_group;