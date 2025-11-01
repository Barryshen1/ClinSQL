WITH admissions_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        -- Calculate age at admission
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
        -- Calculate hospital length of stay in days. Cast to FLOAT64 for accurate calculations.
        CAST(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS FLOAT64) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        -- Filter for age at admission between 81 and 91, inclusive
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
        -- Filter for admissions transferred from other hospitals
        AND adm.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
        -- Ensure dischtime exists for a valid LOS calculation
        AND adm.dischtime IS NOT NULL
),
-- Define discharge groups and filter in a separate CTE for clarity and efficiency
filtered_admissions AS (
    SELECT
        *,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN discharge_location LIKE '%HOME%' THEN 'Home'
            WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
            ELSE NULL
        END AS discharge_group
    FROM admissions_cohort
)
SELECT
    discharge_group,
    COUNT(DISTINCT hadm_id) AS cohort_size,
    AVG(los_days) AS mean_los_days,
    -- Use APPROX_QUANTILES to calculate percentiles, then extract specific values
    (APPROX_QUANTILES(los_days, 100))[OFFSET(25)] AS los_25th_percentile_days,
    (APPROX_QUANTILES(los_days, 100))[OFFSET(50)] AS los_50th_percentile_days, -- Median
    (APPROX_QUANTILES(los_days, 100))[OFFSET(75)] AS los_75th_percentile_days,
    (APPROX_QUANTILES(los_days, 100))[OFFSET(90)] AS los_90th_percentile_days,
    -- Calculate percentage of LOS <= 10 days. SAFE_DIVIDE handles potential division by zero.
    SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(los_days)) * 100 AS percent_los_le_10_days
FROM
    filtered_admissions
WHERE
    discharge_group IS NOT NULL -- Only include the specified discharge groups in the final output
GROUP BY
    discharge_group
ORDER BY
    discharge_group;