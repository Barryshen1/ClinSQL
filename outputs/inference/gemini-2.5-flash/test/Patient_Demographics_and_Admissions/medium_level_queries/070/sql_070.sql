with APPROX_QUANTILES for median (50th percentile)
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
    -- Replaced PERCENTILE_CONT with APPROX_QUANTILES for 75th percentile
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
    -- Replaced PERCENTILE_CONT with APPROX_QUANTILES for 90th percentile
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
    ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(los_days), 2) AS percentile_rank_10_days_or_less
FROM (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        -- Calculate Length of Stay in days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize discharge outcomes
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
            WHEN adm.discharge_location = 'HOME' THEN 'Discharged Home'
            ELSE 'Other Discharge Type' -- Admissions not fitting desired categories
        END AS discharge_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for male ED admissions aged 57-67
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 57 AND 67
        AND adm.admission_type = 'EMERGENCY'
        -- Ensure admission and discharge times are valid for LOS calculation
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
) AS cohort_admissions
WHERE
    -- Only include the specific discharge categories requested
    discharge_category IN ('In-hospital Death', 'Discharged to Hospice', 'Discharged Home')
GROUP BY
    discharge_category
ORDER BY
    discharge_category;