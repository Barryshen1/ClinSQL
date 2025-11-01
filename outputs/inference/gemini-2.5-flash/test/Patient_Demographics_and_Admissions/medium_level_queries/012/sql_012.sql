WITH AdmissionsAnalysis AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        p.gender,
        -- Calculate age at admission using anchor_age and anchor_year
        CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT) AS age_at_admission,
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN a.discharge_location = 'Home' THEN 'Discharged Home'
            WHEN a.discharge_location IN (
                'Home Health Care',
                'Hospice',
                'Other Facility',
                'Rehab',
                'SNF', -- Skilled Nursing Facility
                'ALF', -- Assisted Living Facility
                'Psychiatric Hospital'
            ) THEN 'Discharged to Facility'
            ELSE 'Other/Excluded' -- Catch-all for locations not explicitly asked for
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
)
SELECT
    discharge_group,
    COUNT(hadm_id) AS total_admissions,
    -- Proportion of admissions with LOS >= 7 days
    SAFE_DIVIDE(
        CAST(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0,
        COUNT(hadm_id)
    ) AS proportion_los_ge_7_days,
    -- Percentile rank of 7-day LOS, interpreted as the percentage of admissions with LOS <= 7 days
    SAFE_DIVIDE(
        CAST(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0,
        COUNT(hadm_id)
    ) AS percentile_of_los_le_7_days
FROM
    AdmissionsAnalysis
WHERE
    discharge_group IN ('Discharged Home', 'Discharged to Facility', 'In-hospital Death')
GROUP BY
    discharge_group
ORDER BY
    discharge_group;