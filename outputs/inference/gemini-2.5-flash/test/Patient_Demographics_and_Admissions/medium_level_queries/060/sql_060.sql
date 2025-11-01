WITH cohort_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.discharge_location,
        ad.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        -- Calculate Length of Stay in days
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F' -- Female patients
        AND p.anchor_age BETWEEN 50 AND 60 -- Age 50-60
        AND ad.admission_location = 'EMERGENCY ROOM' -- Admitted from the ED
),
admissions_with_outcome AS (
    SELECT
        *,
        -- Categorize discharge outcome based on the specified criteria
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
            WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST ADVICE') THEN 'Home'
            ELSE NULL -- Filter out other discharge locations not explicitly requested
        END AS discharge_group
    FROM
        cohort_admissions
)
SELECT
    discharge_group,
    CAST(AVG(los_days) AS BIGNUMERIC) AS mean_los_days,
    CAST(STDDEV(los_days) AS BIGNUMERIC) AS stddev_los_days,
    -- Calculate the percentage of admissions with LOS <= 10 days
    CAST(SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS BIGNUMERIC) * 100.0 / COUNT(hadm_id) AS percent_los_le_10_days
FROM
    admissions_with_outcome
WHERE
    discharge_group IS NOT NULL -- Only include the 'Home', 'Hospice', 'In-hospital Death' categories
GROUP BY
    discharge_group
ORDER BY
    discharge_group;