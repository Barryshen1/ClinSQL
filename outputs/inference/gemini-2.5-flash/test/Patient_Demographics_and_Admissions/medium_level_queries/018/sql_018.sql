WITH CohortData AS (
    SELECT
        pat.subject_id,
        adm.hadm_id,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize discharge outcome
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST ADVICE') THEN 'Home'
            -- All other non-null discharge locations are categorized as 'Facility'
            WHEN adm.discharge_location IS NOT NULL THEN 'Facility'
            ELSE 'Unknown' -- Fallback for any unclassified discharge_location, though less likely in this context
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 43 AND 53
        AND adm.admission_location = 'TRANSFER FROM OTHER HEAL FAC/HOSP'
        AND adm.admittime IS NOT NULL -- Ensure valid admission time
        AND adm.dischtime IS NOT NULL -- Ensure valid discharge time for LOS calculation
)
SELECT
    discharge_group,
    -- Median LOS
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    -- Interquartile Range (IQR) of LOS (75th percentile - 25th percentile)
    (APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]) AS iqr_los_days,
    -- Percentage of patients with LOS <= 10 days
    SAFE_DIVIDE(COUNTIF(los_days <= 10) * 100.0, COUNT(los_days)) AS percent_los_le_10_days
FROM
    CohortData
WHERE
    discharge_group != 'Unknown' -- Exclude any records that couldn't be classified into the three specific groups
GROUP BY
    discharge_group
ORDER BY
    CASE discharge_group
        WHEN 'Home' THEN 1
        WHEN 'Facility' THEN 2
        WHEN 'In-hospital Death' THEN 3
        ELSE 4 -- Fallback for any other unexpected group, though the WHERE clause should prevent it
    END;