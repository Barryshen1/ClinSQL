SELECT
    discharge_group,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(STDDEV(los_days), 2) AS stddev_los_days,
    ROUND(SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(los_days), 2) AS percentile_rank_5day_los
FROM
    (
        SELECT
            adm.subject_id,
            adm.hadm_id,
            DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
            CASE
                WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
                WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
                ELSE 'Facility' -- Catches all other non-expired, non-home discharges
            END AS discharge_group
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        WHERE
            pat.gender = 'F'
            AND pat.anchor_age BETWEEN 52 AND 62
            AND adm.admission_type = 'TRANSFER'
            AND adm.admittime IS NOT NULL
            AND adm.dischtime IS NOT NULL
            AND adm.dischtime >= adm.admittime -- Ensure valid LOS
    ) AS cohort_admissions_with_los
GROUP BY
    discharge_group
ORDER BY
    discharge_group;