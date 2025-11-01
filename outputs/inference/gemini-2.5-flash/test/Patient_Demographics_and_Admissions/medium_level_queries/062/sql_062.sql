WITH PatientLOS AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        pa.gender,
        pa.anchor_age,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        ad.hospital_expire_flag,
        ad.discharge_location
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 64 AND 74
        AND ad.dischtime IS NOT NULL -- Ensure a valid discharge time for LOS calculation
        AND ad.admittime IS NOT NULL -- Ensure a valid admit time for LOS calculation
),
AdmissionCategories AS (
    SELECT
        subject_id,
        hadm_id,
        los_days,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
            WHEN LOWER(discharge_location) LIKE '%skilled nursing facility%'
                OR LOWER(discharge_location) LIKE '%rehab%'
                OR LOWER(discharge_location) LIKE '%long term acute care%'
                OR LOWER(discharge_location) LIKE '%ltach%' THEN 'SNF/Rehab/LTACH'
            ELSE 'Other/Unknown' -- Categorize any unspecified discharge locations
        END AS discharge_group
    FROM
        PatientLOS
)
SELECT
    discharge_group,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    -- Proportion of admissions with LOS >= 7 days
    ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS proportion_los_ge_7_days_percent,
    -- 14-day percentile per group (interpreted as the percentile rank of a 14-day LOS)
    ROUND(SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS los_le_14_day_percentile_rank
FROM
    AdmissionCategories
WHERE
    discharge_group IN ('Home', 'SNF/Rehab/LTACH', 'In-hospital Death') -- Filter for the specific discharge groups requested
GROUP BY
    discharge_group
ORDER BY
    discharge_group;