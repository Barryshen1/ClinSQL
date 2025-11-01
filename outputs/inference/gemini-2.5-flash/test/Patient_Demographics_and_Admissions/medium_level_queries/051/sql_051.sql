WITH QualifiedAdmissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        pat.gender,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 68 AND 78
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0 -- Ensure LOS is non-negative
)
SELECT
    qa.discharge_location AS discharge_status,
    ROUND(AVG(CAST(qa.los_days AS FLOAT64)), 2) AS mean_los_days,
    ROUND(STDDEV(CAST(qa.los_days AS FLOAT64)), 2) AS std_dev_los_days,
    ROUND((COUNTIF(qa.los_days <= 7) * 100.0 / COUNT(*)), 2) AS percent_los_le_7_days
FROM
    QualifiedAdmissions AS qa
GROUP BY
    qa.discharge_location
ORDER BY
    qa.discharge_location;