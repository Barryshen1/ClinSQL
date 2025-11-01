SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    PERCENTILE_CONT(los_days, 0.5) AS median_los,
    (SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_le_5_days
FROM (
    SELECT
        a.hospital_expire_flag,
        EXTRACT(DAY FROM (COALESCE(a.dischtime, a.deathtime) - a.admittime)) AS los_days
    FROM
        physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN
        physionet-data.mimiciv_3_1_hosp.patients p
    ON
        a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 41 AND 51
        AND a.admission_location = 'EMERGENCY ROOM'
) AS los_calc
GROUP BY
    hospital_expire_flag
ORDER BY
    hospital_expire_flag;