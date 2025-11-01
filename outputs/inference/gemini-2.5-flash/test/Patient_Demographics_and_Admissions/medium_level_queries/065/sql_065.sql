SELECT
    CASE
        WHEN ad.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
        WHEN ad.discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
        WHEN ad.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Discharged Home'
        ELSE 'Unknown Discharge' -- Catch-all, though the WHERE clause should narrow it down enough
    END AS discharge_group,
    COUNT(DISTINCT ad.subject_id) AS num_subjects,
    COUNT(*) AS num_admissions,
    AVG(DATE_DIFF(ad.dischtime, ad.admittime, DAY)) AS mean_los_days,
    STDDEV(DATE_DIFF(ad.dischtime, ad.admittime, DAY)) AS stddev_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND ad.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
    -- Filter out admissions that had any ICU stay
    AND NOT EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE icu.hadm_id = ad.hadm_id
    )
    -- Select only the discharge groups specified in the question
    AND (
        ad.hospital_expire_flag = 1
        OR ad.discharge_location = 'HOSPICE'
        OR ad.discharge_location IN ('HOME', 'HOME HEALTH CARE')
    )
GROUP BY
    discharge_group
ORDER BY
    discharge_group;