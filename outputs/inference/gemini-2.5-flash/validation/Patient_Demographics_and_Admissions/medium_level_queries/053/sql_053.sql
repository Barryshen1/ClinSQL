SELECT
    discharge_group,
    COUNT(los_days) AS num_admissions,
    -- Calculate Median (50th percentile)
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    -- Calculate Interquartile Range (IQR = Q3 - Q1)
    (APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]) AS iqr_los_days
FROM
    (
        SELECT
            adm.subject_id,
            DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
            CASE
                WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
                WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Discharged Home'
                WHEN adm.discharge_location = 'HOSPICE' THEN 'Discharged Hospice'
                ELSE NULL -- Exclude other discharge locations not specified in the question
            END AS discharge_group
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        WHERE
            pat.gender = 'F'
            AND pat.anchor_age BETWEEN 77 AND 87
            AND adm.admission_type = 'EMERGENCY'
            AND adm.dischtime IS NOT NULL -- Ensure LoS can be calculated
    ) AS admissions_filtered
WHERE
    discharge_group IS NOT NULL -- Only include the three specified discharge outcomes
GROUP BY
    discharge_group
ORDER BY
    discharge_group;