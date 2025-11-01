WITH PatientLOS_Base AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            ELSE 'Discharged Alive'
        END AS discharge_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 83 AND 93
        AND adm.dischtime IS NOT NULL
        AND adm.admittime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 >= 0
)
SELECT
    discharge_status,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(PERCENTILE_CONT(0.5 ORDER BY los_days), 2) AS median_los_days, -- p50
    ROUND(PERCENTILE_CONT(0.75 ORDER BY los_days), 2) AS p75_los_days,
    ROUND(PERCENTILE_CONT(0.90 ORDER BY los_days), 2) AS p90_los_days,
    ROUND(SAFE_DIVIDE(COUNT(CASE WHEN los_days <= 5 THEN 1 END) * 100.0, COUNT(los_days)), 2) AS percentile_rank_5_day_los
FROM
    PatientLOS_Base
GROUP BY
    discharge_status
ORDER BY
    discharge_status;