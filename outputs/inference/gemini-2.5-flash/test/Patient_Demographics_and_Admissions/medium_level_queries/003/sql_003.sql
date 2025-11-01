WITH admissions_cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate Length of Stay in days.
        -- DATE_DIFF(DATE_TRUNC(timestamp_expression, DAY), DATE_TRUNC(timestamp_expression, DAY), DAY)
        -- is preferred for "days stayed" as an integer, where a stay crossing day boundary counts as 1 day.
        DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
        -- Categorize discharge outcomes based on the question's requirements
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
            WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
            ELSE NULL -- Filter out other discharge locations later
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Male patients
        AND p.anchor_age BETWEEN 80 AND 90 -- Aged 80-90 years
        AND a.admission_type != 'EMERGENCY' -- Non-emergency admissions
        AND a.dischtime IS NOT NULL -- Ensure valid discharge time for LOS calculation
        AND a.admittime IS NOT NULL -- Ensure valid admission time for LOS calculation
        AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) >= 0 -- Ensure LOS is non-negative
)
SELECT
    discharge_group,
    COUNT(hadm_id) AS total_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    -- Calculate approximate percentiles for LOS distribution using APPROX_QUANTILES
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
    -- Calculate percentage of stays <= 14 days
    ROUND(SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(los_days), 2) AS percent_los_le_14_days
FROM
    admissions_cohort
WHERE
    discharge_group IS NOT NULL -- Only include 'Home', 'Hospice', and 'In-hospital Death'
GROUP BY
    discharge_group
ORDER BY
    discharge_group;